// End-to-end test of the trigger eval runner.
//
// A stub `pi` stands in for the real harness, so the test covers workspace
// preparation, process spawning, trace capture, scoring, and report writing
// without a model or credentials. What it cannot cover is whether a real model
// picks the right skill; that is what the live run is for.

import { execFile } from "node:child_process";
import { existsSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { test } from "node:test";

import { parseDataset } from "../lib/csv.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, "..", "..");
const RUNNER = join(REPO_ROOT, "evals", "run-trigger-evals.mjs");
const DATASET = join(REPO_ROOT, "evals", "triggers.csv");
const STUB = join(HERE, "fixtures", "stub-pi.mjs");

function runRunner(args, env = {}) {
  return new Promise((resolvePromise) => {
    execFile(
      process.execPath,
      [RUNNER, ...args],
      { env: { ...process.env, ...env }, maxBuffer: 32 * 1024 * 1024 },
      (error, stdout, stderr) => resolvePromise({ code: error?.code ?? 0, stdout, stderr }),
    );
  });
}

function readReport(stdout) {
  const match = stdout.match(/Report: (.+report\.md)/);
  assert.ok(match, `no report path in output:\n${stdout}`);
  return { path: match[1], markdown: readFileSync(match[1], "utf8"), dir: dirname(match[1]) };
}

test("--list prints the dataset without launching pi", async () => {
  const result = await runRunner(["--list"]);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^e01\s+entry\s+speq-mission\s+trigger$/m);
  // The dataset grows, so count it rather than pinning a number the next row breaks.
  const rows = parseDataset(readFileSync(DATASET, "utf8")).length;
  assert.match(result.stdout, new RegExp(`${rows} rows\\.`));
});

test("--dry-run prints the pi command for each selected row", async () => {
  const result = await runRunner(["--dry-run", "--model", "stub/model", "--set", "source", "--only", "e03,b02"]);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /--skill .*\.claude\/skills\/speq-plan /);
  assert.match(result.stdout, /--model stub\/model/);
  assert.ok(result.stdout.includes("Plan it before you touch any code"));
});

test("a missing model is rejected before any run starts", async () => {
  const result = await runRunner([]);
  assert.equal(result.code, 2);
  assert.match(result.stderr, /--model is required/);
});

test("an unknown row id is rejected before any run starts", async () => {
  const result = await runRunner(["--model", "stub/model", "--only", "nope"]);
  assert.equal(result.code, 2);
  assert.match(result.stderr, /unknown row id/);
});

test("the runner scores a stub run and writes a report", async () => {
  // The stub reports exactly one loaded skill, so the row that expects it must
  // pass and the row that expects a different skill must fail.
  const result = await runRunner(
    ["--model", "stub/model", "--set", "source", "--runs", "1", "--only", "e03,e05", "--pi-cmd", `${process.execPath} ${STUB}`],
    { STUB_PI_SKILLS: "speq-plan" },
  );

  assert.equal(result.code, 1, `expected a non-zero exit because one row fails\n${result.stdout}`);
  const report = readReport(result.stdout);

  try {
    assert.match(report.markdown, /\*\*1 of 2 rows pass \(50%\)\.\*\*/);
    assert.match(report.markdown, /\| e03 \| entry \| speq-plan \| trigger \| PASS \| 1\/1 \|/);
    assert.match(report.markdown, /\| e05 \| entry \| speq-implement \| trigger \| FAIL \| 0\/1 \|/);
    assert.match(report.markdown, /### e05: speq-implement should trigger/);

    assert.ok(existsSync(join(report.dir, "report.json")));
    assert.ok(existsSync(join(report.dir, "e03", "run-1.jsonl")));
    assert.ok(existsSync(join(report.dir, "e05", "run-1.jsonl")));

    const json = JSON.parse(readFileSync(join(report.dir, "report.json"), "utf8"));
    assert.equal(json.totals.scored, 2);
    assert.equal(json.totals.pass, 1);
    assert.equal(json.meta.skillSet, "source");
    assert.equal(json.meta.piCmd, `${process.execPath} ${STUB}`);
    assert.equal(json.rows.find((row) => row.id === "e03").noise.length, 0);
  } finally {
    rmSync(report.dir, { recursive: true, force: true });
  }
});

test("a negative row fails when the stub loads the forbidden skill", async () => {
  const result = await runRunner(
    ["--model", "stub/model", "--set", "source", "--runs", "1", "--only", "n01", "--pi-cmd", `${process.execPath} ${STUB}`],
    { STUB_PI_SKILLS: "speq-planning" },
  );

  assert.equal(result.code, 1);
  const report = readReport(result.stdout);
  try {
    assert.match(report.markdown, /\| n01 \| internal-negative \| speq-planning \| no trigger \| FAIL \| 0\/1 \|/);
  } finally {
    rmSync(report.dir, { recursive: true, force: true });
  }
});

test("a run that never reaches the model is reported as an error, not a failure", async () => {
  const result = await runRunner(
    ["--model", "stub/model", "--set", "source", "--runs", "1", "--only", "e03", "--pi-cmd", "false"],
  );

  assert.equal(result.code, 1);
  const report = readReport(result.stdout);
  try {
    assert.match(report.markdown, /\| e03 \| entry \| speq-plan \| trigger \| ERROR \| 0\/0 \|/);
    assert.match(report.markdown, /0 of 0 rows pass/);
  } finally {
    rmSync(report.dir, { recursive: true, force: true });
  }
});

test("--baseline writes a comparable report and records the skill tree hash", async () => {
  const name = `test-baseline-${process.pid}`;
  const path = join(REPO_ROOT, "evals", "baselines", `${name}.md`);

  try {
    const result = await runRunner(
      ["--model", "stub/model", "--set", "source", "--runs", "1", "--only", "e03", "--baseline", name, "--pi-cmd", `${process.execPath} ${STUB}`],
      { STUB_PI_SKILLS: "speq-plan" },
    );
    assert.match(result.stdout, new RegExp(`Baseline: .*${name}\\.md`));
    assert.ok(existsSync(path), `expected ${path}`);

    const baseline = readFileSync(path, "utf8");
    assert.match(baseline, /- Skill tree hash: `[0-9a-f]{12}`/);
    assert.match(baseline, /- Commit: `[0-9a-f]+`/);
    assert.match(baseline, /\*\*1 of 1 rows pass \(100%\)\.\*\*/);
  } finally {
    rmSync(path, { force: true });
    const reportDir = readdirSync(join(REPO_ROOT, "evals", "artifacts"), { withFileTypes: true })
      .map((entry) => join(REPO_ROOT, "evals", "artifacts", entry.name))
      .sort()
      .at(-1);
    if (reportDir) rmSync(reportDir, { recursive: true, force: true });
  }
});

test("a pi command that ignores --version cannot inject output into the report", async () => {
  const result = await runRunner(
    ["--model", "stub/model", "--set", "source", "--runs", "1", "--only", "e03", "--pi-cmd", `${process.execPath} ${STUB}`],
    { STUB_PI_SKILLS: "speq-plan", STUB_PI_IGNORE_VERSION: "1" },
  );
  const report = readReport(result.stdout);
  try {
    assert.doesNotMatch(report.markdown, /- Pi version:/);
    assert.doesNotMatch(report.markdown, /\{"type":"session"/);
  } finally {
    rmSync(report.dir, { recursive: true, force: true });
  }
});

test("an invalid baseline name is rejected before any run starts", async () => {
  const result = await runRunner(["--model", "stub/model", "--baseline", "../escape"]);
  assert.equal(result.code, 2);
  assert.match(result.stderr, /--baseline must be a plain file name/);
});

test("a unanimous vote is not reported as flaky", async () => {
  const result = await runRunner(
    ["--model", "stub/model", "--set", "source", "--runs", "3", "--only", "e03", "--pi-cmd", `${process.execPath} ${STUB}`],
    { STUB_PI_SKILLS: "speq-plan" },
  );
  const report = readReport(result.stdout);
  try {
    assert.match(report.markdown, /\| e03 \| entry \| speq-plan \| trigger \| PASS \| 3\/3 \|/);
    assert.match(report.markdown, /## Not unanimous\n\nNone\./);
  } finally {
    rmSync(report.dir, { recursive: true, force: true });
  }
});

test("a split vote passes on the majority and is flagged", async () => {
  // Two of three runs load the skill. The row passes, and the split is
  // reported so a flaky row cannot hide inside a green score.
  const state = join(tmpdir(), `speq-eval-stub-${process.pid}-${Date.now()}.count`);
  const result = await runRunner(
    ["--model", "stub/model", "--set", "source", "--runs", "3", "--only", "e03", "--pi-cmd", `${process.execPath} ${STUB}`],
    { STUB_PI_SKILLS: "speq-plan", STUB_PI_STATE: state, STUB_PI_LOAD_ON: "1,2" },
  );
  const report = readReport(result.stdout);
  try {
    assert.match(report.markdown, /\| e03 \| entry \| speq-plan \| trigger \| PASS \| 2\/3 \|/);
    assert.match(report.markdown, /\| e03 \| speq-plan \| trigger \| 2\/3 \|/);
  } finally {
    rmSync(report.dir, { recursive: true, force: true });
    rmSync(state, { force: true });
  }
});
