// Unit tests for the trigger eval's reading and scoring logic.
//
// These run without a model, so the grader is verified before any prompt is
// spent. The trace fixtures under test/fixtures/ pin the two failure modes
// that would silently corrupt every score: counting the system prompt's
// advertised skill list as a load, and confusing `speq-plan` with
// `speq-plan-pr`.

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { test } from "node:test";

import { parseCsvRows, parseDataset, validateDataset } from "../lib/csv.mjs";
import { buildReport, gradeRow, renderMarkdown } from "../lib/grade.mjs";
import { advertisedSkills, loadedSkills, parseJsonl, summarizeRun } from "../lib/trace.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, "fixtures");
const REPO_ROOT = resolve(HERE, "..", "..");
const DATASET_PATH = join(HERE, "..", "triggers.csv");
const PAYLOAD_TREE = join(REPO_ROOT, "dist", "marketplace", "pi", "skills");

function fixtureEvents(name) {
  return parseJsonl(readFileSync(join(FIXTURES, `${name}.jsonl`), "utf8"));
}

function okRun(loaded) {
  return { status: "ok", loaded, advertised: [], stats: {} };
}

test("csv reader handles quoted commas, doubled quotes, and quoted newlines", () => {
  const rows = parseCsvRows('a,b\n"one, two","he said ""hi"""\n"line\nbreak",z\n');
  assert.deepEqual(rows, [
    ["a", "b"],
    ["one, two", 'he said "hi"'],
    ["line\nbreak", "z"],
  ]);
});

test("dataset reader maps headers and skips comments and blank lines", () => {
  const records = parseDataset("# comment\nid,class\n\ne01,entry\n");
  assert.deepEqual(records, [{ id: "e01", class: "entry" }]);
});

test("dataset validation reports every shape problem", () => {
  const problems = validateDataset([
    { id: "a", class: "entry", skill: "s", should_trigger: "true", prompt: "p", rationale: "r" },
    { id: "a", class: "nope", skill: "s", should_trigger: "maybe", prompt: "", rationale: "r" },
  ]);
  assert.equal(problems.length, 4, problems.join("; "));
  assert.ok(problems.some((p) => p.includes("duplicate id")));
  assert.ok(problems.some((p) => p.includes("unknown class")));
  assert.ok(problems.some((p) => p.includes("should_trigger must be")));
  assert.ok(problems.some((p) => p.includes("missing prompt")));
});

test("jsonl reader survives a truncated trailing record", () => {
  const events = parseJsonl('{"type":"agent_start"}\n{"type":"turn_st');
  assert.deepEqual(events, [{ type: "agent_start" }]);
});

test("a skill read in a tool call counts as loaded", () => {
  assert.deepEqual([...loadedSkills(fixtureEvents("read-target-skill"))], ["speq-plan"]);
});

test("an advertised skill that was never read does not count as loaded", () => {
  const events = fixtureEvents("advertised-only");
  assert.deepEqual([...loadedSkills(events)], []);
  assert.deepEqual([...advertisedSkills(events)].sort(), ["speq-plan", "speq-plan-pr"]);
});

test("a sibling skill load is not misread as its prefix", () => {
  assert.deepEqual([...loadedSkills(fixtureEvents("sibling-skill"))], ["speq-plan-pr"]);
});

test("reading a reference file counts as loading its skill", () => {
  assert.deepEqual([...loadedSkills(fixtureEvents("reference-file"))], ["speq-plan"]);
});

test("listing a skill directory is not a load", () => {
  assert.deepEqual([...loadedSkills(fixtureEvents("ls-only"))], []);
});

test("every loaded skill in a run is reported", () => {
  assert.deepEqual(
    [...loadedSkills(fixtureEvents("two-skills"))].sort(),
    ["speq-code-guardrails", "speq-plan"],
  );
});

test("a skill read through codemode counts as loaded", () => {
  assert.deepEqual([...loadedSkills(fixtureEvents("codemode-read"))], ["speq-cli"]);
});

test("run summary reports loaded skills and token totals", () => {
  const summary = summarizeRun(fixtureEvents("read-target-skill"));
  assert.deepEqual(summary.loaded, ["speq-plan"]);
  assert.equal(summary.stats.inputTokens, 1200);
  assert.equal(summary.stats.totalTokens, 1240);
});

const row = { id: "x", class: "entry", skill: "speq-plan", should_trigger: "true", prompt: "p", rationale: "r" };

test("a row that passes two of three runs passes and is marked flaky", () => {
  const graded = gradeRow(row, [okRun(["speq-plan"]), okRun(["speq-plan"]), okRun([])]);
  assert.equal(graded.verdict, "PASS");
  assert.equal(graded.passes, 2);
  assert.equal(graded.flaky, true);
});

test("a row that passes one of three runs fails", () => {
  const graded = gradeRow(row, [okRun(["speq-plan"]), okRun([]), okRun([])]);
  assert.equal(graded.verdict, "FAIL");
  assert.equal(graded.passes, 1);
});

test("a unanimous pass is not flaky and reports no noise", () => {
  const graded = gradeRow(row, [okRun(["speq-plan"]), okRun(["speq-plan"]), okRun(["speq-plan"])]);
  assert.equal(graded.verdict, "PASS");
  assert.equal(graded.flaky, false);
  assert.deepEqual(graded.noise, []);
});

test("extra loaded skills are reported as noise", () => {
  const graded = gradeRow(row, [
    okRun(["speq-plan", "speq-planning"]),
    okRun(["speq-plan"]),
    okRun(["speq-plan"]),
  ]);
  assert.deepEqual(graded.noise, ["speq-planning"]);
});

test("a negative row fails when the skill loads anyway", () => {
  const negative = { ...row, should_trigger: "false" };
  assert.equal(gradeRow(negative, [okRun(["speq-plan"]), okRun(["speq-plan"]), okRun(["speq-plan"])]).verdict, "FAIL");
  assert.equal(gradeRow(negative, [okRun([]), okRun([]), okRun([])]).verdict, "PASS");
});

test("a row whose runs never reached the model is an error, not a failure", () => {
  const errorRun = { status: "error", loaded: [], advertised: [], stats: {}, error: "no API key" };
  const graded = gradeRow(row, [errorRun, errorRun, errorRun]);
  assert.equal(graded.verdict, "ERROR");
  assert.equal(graded.detail, "no API key");
});

test("a row with one usable run still scores from the usable runs", () => {
  const errorRun = { status: "error", loaded: [], advertised: [], stats: {}, error: "boom" };
  const graded = gradeRow(row, [okRun(["speq-plan"]), errorRun, errorRun]);
  assert.equal(graded.verdict, "PASS");
  assert.equal(graded.usableRuns, 1);
  assert.equal(graded.errors, 2);
});

test("the report aggregates by class and renders failure detail", () => {
  const graded = [
    gradeRow({ ...row, id: "a", class: "entry" }, [okRun(["speq-plan"]), okRun(["speq-plan"]), okRun(["speq-plan"])]),
    gradeRow({ ...row, id: "b", class: "entry" }, [okRun([]), okRun([]), okRun([])]),
    gradeRow({ ...row, id: "c", class: "boundary", should_trigger: "false" }, [okRun([]), okRun([]), okRun([])]),
  ];
  const report = buildReport(graded, { model: "test/model", skillSet: "payload", skillCount: 20, tree: "/t", runs: 3, dataset: "evals/triggers.csv", datasetRows: 3, startedAt: "now" });

  assert.equal(report.totals.scored, 3);
  assert.equal(report.totals.pass, 2);
  assert.equal(report.totals.fail, 1);
  assert.equal(report.byClass.entry.pass, 1);
  assert.equal(report.byClass.boundary.pass, 1);

  const markdown = renderMarkdown(report);
  assert.ok(markdown.includes("2 of 3 rows pass"));
  assert.ok(markdown.includes("### b: speq-plan should trigger"));
  assert.ok(markdown.includes("Why this expectation"));
});

test("the shipped dataset is valid and covers every skill from both sides", () => {
  const records = parseDataset(readFileSync(DATASET_PATH, "utf8"));
  assert.deepEqual(validateDataset(records), []);

  const named = new Set(records.map((record) => record.skill));
  const positive = new Set(records.filter((record) => record.should_trigger === "true").map((record) => record.skill));
  const negative = new Set(records.filter((record) => record.should_trigger === "false").map((record) => record.skill));

  if (existsSync(PAYLOAD_TREE)) {
    const onDisk = readdirSync(PAYLOAD_TREE, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && existsSync(join(PAYLOAD_TREE, entry.name, "SKILL.md")))
      .map((entry) => entry.name);
    assert.deepEqual([...named].filter((s) => !onDisk.includes(s)).sort(), [], "dataset names skills that do not exist");
    assert.deepEqual(onDisk.filter((s) => !named.has(s)).sort(), [], "skill tree has skills the dataset never tests");
  }

  for (const skill of named) {
    assert.ok(positive.has(skill), `${skill} has no should_trigger=true row`);
    assert.ok(negative.has(skill), `${skill} has no should_trigger=false row`);
  }
});
