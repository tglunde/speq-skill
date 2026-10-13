#!/usr/bin/env node
// Trigger eval runner: does each skill load when it should, and stay away when
// it should not?
//
// For every row in evals/triggers.csv the runner prepares a throwaway speq
// project, runs the prompt against Pi with exactly one skill tree visible,
// captures the JSONL trace, and scores which skills the run loaded.
//
// Usage:
//   node evals/run-trigger-evals.mjs --model <provider/id> [options]
//
// Run `node evals/run-trigger-evals.mjs --help` for the full option list.

import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parseDataset, validateDataset } from "./lib/csv.mjs";
import { buildReport, gradeRow, renderMarkdown } from "./lib/grade.mjs";
import { parseJsonl, summarizeRun } from "./lib/trace.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, "..");
const DATASET_PATH = join(HERE, "triggers.csv");
const WORKSPACE_FIXTURE = join(HERE, "fixtures", "workspace");
const ARTIFACTS_DIR = join(HERE, "artifacts");

const SKILL_SETS = {
  payload: join(REPO_ROOT, "dist", "marketplace", "pi", "skills"),
  source: join(REPO_ROOT, ".claude", "skills"),
};

// Pi arguments that make a run comparable across rows and cheap to repeat.
//
// --no-skills      ignore the user-level skill trees, so a stale installed
//                  marketplace cannot answer a prompt for us
// --no-mcp         no MCP startup latency; this eval measures selection only
// --no-session     nothing is written outside the artifact directory
// --approve        trust the throwaway workspace so a trust prompt cannot
//                  stall a non-interactive run
//
// Pi extensions are disabled too, but through --with-extensions so the
// operator can put them back. See buildPiArgs.
const PI_BASE_ARGS = [
  "--mode",
  "json",
  "--no-session",
  "--no-skills",
  "--no-mcp",
  "--approve",
];

function parseArgs(argv) {
  const options = {
    model: null,
    provider: null,
    thinking: null,
    skillSet: "payload",
    runs: 3,
    timeout: 180,
    concurrency: 1,
    only: null,
    classes: null,
    dryRun: false,
    list: false,
    keepWorkspace: false,
    withExtensions: false,
    workspaceRoot: null,
    extraArgs: [],
    piCmd: "pi",
    baseline: null,
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      i += 1;
      if (i >= argv.length) fail(`missing value for ${arg}`);
      return argv[i];
    };
    switch (arg) {
      case "--model": options.model = next(); break;
      case "--provider": options.provider = next(); break;
      case "--thinking": options.thinking = next(); break;
      case "--set": options.skillSet = next(); break;
      case "--runs": options.runs = Number(next()); break;
      case "--timeout": options.timeout = Number(next()); break;
      case "--concurrency": options.concurrency = Number(next()); break;
      case "--only": options.only = next().split(",").map((s) => s.trim()).filter(Boolean); break;
      case "--class": options.classes = next().split(",").map((s) => s.trim()).filter(Boolean); break;
      case "--workspace-root": options.workspaceRoot = next(); break;
      case "--extra-arg": options.extraArgs.push(next()); break;
      case "--pi-cmd": options.piCmd = next(); break;
      case "--baseline": options.baseline = next(); break;
      case "--dry-run": options.dryRun = true; break;
      case "--list": options.list = true; break;
      case "--keep-workspace": options.keepWorkspace = true; break;
      case "--with-extensions": options.withExtensions = true; break;
      case "--help":
      case "-h": options.help = true; break;
      default: fail(`unknown option ${arg}`);
    }
  }

  return options;
}

function fail(message) {
  process.stderr.write(`error: ${message}\n`);
  process.exit(2);
}

const HELP = `Trigger eval runner

  node evals/run-trigger-evals.mjs --model <provider/id> [options]

Required
  --model <pattern>      Pi model, e.g. opencode-go/gpt-6-luna

Options
  --provider <name>      Restrict --model lookup to one provider
  --thinking <level>     off|minimal|low|medium|high|xhigh|max
  --set <payload|source> Which skill tree to advertise (default: payload)
  --runs <n>             Runs per row, majority vote (default: 3)
  --timeout <seconds>    Per-run wall clock limit (default: 180)
  --concurrency <n>      Rows in flight (default: 1)
  --only <id,id>         Run only these dataset rows
  --class <c,c>          Run only these classes: entry, boundary,
                         internal-negative, internal-positive
  --list                 Print the dataset and exit
  --dry-run              Print the Pi command for each row and exit
  --keep-workspace       Keep the throwaway workspaces
  --with-extensions      Re-enable Pi extensions (off by default)
  --workspace-root <dir> Where to create throwaway workspaces (default: tmp)
  --pi-cmd <command>     How to launch Pi (default: pi). Use this when Pi needs
                         a credential wrapper, for example
                         --pi-cmd "fnox proxy run -- pi". Split on spaces.
  --baseline <name>      Copy the report to evals/baselines/<name>.md
  --extra-arg <arg>      Extra argument passed to Pi (repeatable)
  --help                 This text
`;

function resolveSkillTree(skillSet) {
  const tree = SKILL_SETS[skillSet];
  if (!tree) fail(`unknown --set ${skillSet}, expected payload or source`);
  if (!existsSync(tree)) {
    fail(
      skillSet === "payload"
        ? `skill tree not found: ${tree}\nRun ./scripts/plugin/build.sh first, or use --set source.`
        : `skill tree not found: ${tree}`,
    );
  }
  return tree;
}

function listSkills(tree) {
  return readdirSync(tree, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(join(tree, entry.name, "SKILL.md")))
    .map((entry) => entry.name)
    .sort();
}

function selectRows(rows, options) {
  let selected = rows;
  if (options.only) {
    const wanted = new Set(options.only);
    const missing = [...wanted].filter((id) => !rows.some((row) => row.id === id));
    if (missing.length > 0) fail(`unknown row id(s): ${missing.join(", ")}`);
    selected = selected.filter((row) => wanted.has(row.id));
  }
  if (options.classes) {
    const wanted = new Set(options.classes);
    selected = selected.filter((row) => wanted.has(row.class));
  }
  return selected;
}

function buildPiArgs(options, tree, skills, prompt) {
  const args = [...PI_BASE_ARGS];
  if (!options.withExtensions) args.push("--no-extensions");

  for (const skill of skills) args.push("--skill", join(tree, skill));
  if (options.provider) args.push("--provider", options.provider);
  args.push("--model", options.model);
  if (options.thinking) args.push("--thinking", options.thinking);
  args.push(...options.extraArgs);
  args.push(prompt);
  return args;
}

function prepareWorkspace(row, runIndex, options) {
  const root = options.workspaceRoot ?? tmpdir();
  mkdirSync(root, { recursive: true });
  const dir = mkdtempSync(join(root, `speq-eval-${row.id}-${runIndex}-`));
  cpSync(WORKSPACE_FIXTURE, dir, { recursive: true });

  // A git repository makes the git-shaped prompts real without any remote.
  const git = (args) =>
    new Promise((resolvePromise) => {
      const child = spawn("git", args, { cwd: dir, stdio: "ignore" });
      child.on("close", resolvePromise);
      child.on("error", () => resolvePromise(1));
    });
  return (async () => {
    await git(["init", "-q"]);
    await git(["-c", "user.email=eval@speq.invalid", "-c", "user.name=speq eval", "add", "-A"]);
    await git(["-c", "user.email=eval@speq.invalid", "-c", "user.name=speq eval", "commit", "-qm", "initial"]);
    return dir;
  })();
}

function runPi({ cwd, args, timeoutSeconds, piCommand }) {
  return new Promise((resolvePromise) => {
    const child = spawn(piCommand[0], [...piCommand.slice(1), ...args], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;

    child.stdout.on("data", (chunk) => { stdout += chunk.toString("utf8"); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString("utf8"); });

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 5000);
    }, timeoutSeconds * 1000);

    child.on("error", (error) => {
      clearTimeout(timer);
      resolvePromise({ code: null, stdout, stderr: `${stderr}\n${error.message}`, timedOut });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolvePromise({ code, stdout, stderr, timedOut });
    });
  });
}

async function executeRow(row, options, tree, skills, runDir) {
  const runs = [];
  const piCommand = splitCommand(options.piCmd);

  for (let runIndex = 1; runIndex <= options.runs; runIndex += 1) {
    const workspace = await prepareWorkspace(row, runIndex, options);
    const args = buildPiArgs(options, tree, skills, row.prompt);
    const result = await runPi({
      cwd: workspace,
      args,
      timeoutSeconds: options.timeout,
      piCommand,
    });

    const tracePath = join(runDir, `run-${runIndex}.jsonl`);
    writeFileSync(tracePath, result.stdout, "utf8");
    if (result.stderr.trim() !== "") {
      writeFileSync(join(runDir, `run-${runIndex}.stderr.txt`), result.stderr, "utf8");
    }

    const events = parseJsonl(result.stdout);
    const summary = summarizeRun(events);

    // A run with no assistant message and no tool call never reached the model.
    const reachedModel = events.some((event) => event.type === "message_end" || event.type === "tool_execution_start");
    const status = reachedModel ? "ok" : "error";

    runs.push({
      status,
      ...summary,
      tracePath,
      timedOut: result.timedOut,
      exitCode: result.code,
      error:
        status === "ok"
          ? undefined
          : result.timedOut
            ? `timed out after ${options.timeout}s`
            : result.stderr.trim().split("\n").slice(0, 3).join(" ") || `pi exited ${result.code} with no events`,
    });

    if (!options.keepWorkspace) rmSync(workspace, { recursive: true, force: true });

    const mark = status === "ok" ? (runs.at(-1).loaded.join(",") || "none") : `ERROR (${runs.at(-1).error})`;
    process.stdout.write(`  ${row.id} run ${runIndex}/${options.runs}: ${mark}\n`);
  }

  return runs;
}

// The version line is decoration in the report, so a command that ignores
// --version must not be able to inject its output into it. Only a short,
// version-shaped first line is kept.
function readPiVersion(piCommand) {
  return new Promise((resolvePromise) => {
    const child = spawn(piCommand[0], [...piCommand.slice(1), "--version"], {
      stdio: ["ignore", "pipe", "ignore"],
    });
    let out = "";
    child.stdout.on("data", (chunk) => { out += chunk.toString("utf8"); });
    child.on("error", () => resolvePromise(null));
    child.on("close", () => {
      const line = out.split("\n").map((value) => value.trim()).find((value) => value !== "") ?? "";
      const looksLikeVersion = line.length > 0 && line.length <= 40 && /\d/.test(line) && !line.startsWith("{");
      resolvePromise(looksLikeVersion ? line : null);
    });
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(HELP);
    return;
  }
  if (!options.list && !options.dryRun && !options.model) {
    fail("--model is required. See --help.");
  }

  const datasetText = readFileSync(DATASET_PATH, "utf8");
  const allRows = parseDataset(datasetText);
  const problems = validateDataset(allRows);
  if (problems.length > 0) {
    fail(`dataset is invalid:\n  ${problems.join("\n  ")}`);
  }

  const rows = selectRows(allRows, options);
  if (rows.length === 0) fail("no rows selected");

  if (options.list) {
    const width = Math.max(...rows.map((row) => row.id.length));
    for (const row of rows) {
      process.stdout.write(
        `${row.id.padEnd(width)}  ${row.class.padEnd(17)}  ${row.skill.padEnd(24)}  ${row.should_trigger === "true" ? "trigger" : "no trigger"}\n`,
      );
    }
    process.stdout.write(`\n${rows.length} rows.\n`);
    return;
  }

  // Validate the baseline name before any run starts, so a typo cannot cost a
  // full eval and then throw the result away.
  if (options.baseline && !/^[A-Za-z0-9._-]+$/.test(options.baseline)) {
    fail(`--baseline must be a plain file name, got ${options.baseline}`);
  }

  const tree = resolveSkillTree(options.skillSet);
  const skills = listSkills(tree);
  // A repo-relative path keeps committed baselines comparable across machines.
  const treeLabel = relative(REPO_ROOT, tree).startsWith("..") ? tree : relative(REPO_ROOT, tree);

  if (options.dryRun) {
    for (const row of rows) {
      process.stdout.write(`# ${row.id} (${row.class}, ${row.skill}, should_trigger=${row.should_trigger})\n`);
      const argv = [...splitCommand(options.piCmd), ...buildPiArgs(options, tree, skills, row.prompt)];
      process.stdout.write(`${argv.map(quoteForShell).join(" ")}\n\n`);
    }
    return;
  }

  const startedAt = new Date().toISOString();
  const runId = startedAt.replace(/[:.]/g, "-");
  const runRoot = join(ARTIFACTS_DIR, runId);
  mkdirSync(runRoot, { recursive: true });

  process.stdout.write(
    `Trigger eval: ${rows.length} rows x ${options.runs} runs against ${skills.length} skills in ${tree}\n` +
      `Model: ${options.model}\nArtifacts: ${runRoot}\n\n`,
  );

  const graded = [];
  let cursor = 0;
  const worker = async () => {
    while (cursor < rows.length) {
      const row = rows[cursor];
      cursor += 1;
      const runDir = join(runRoot, row.id);
      mkdirSync(runDir, { recursive: true });
      const runs = await executeRow(row, options, tree, skills, runDir);
      const result = gradeRow(row, runs);
      graded.push(result);
      process.stdout.write(`  ${row.id} -> ${result.verdict} (${result.passes}/${result.usableRuns})\n`);
    }
  };

  const workers = Array.from({ length: Math.max(1, options.concurrency) }, worker);
  await Promise.all(workers);

  graded.sort((a, b) => a.id.localeCompare(b.id));

  const report = buildReport(graded, {
    model: options.model,
    provider: options.provider ?? "(default)",
    thinking: options.thinking ?? "(default)",
    skillSet: options.skillSet,
    skillCount: skills.length,
    tree: treeLabel,
    runs: options.runs,
    timeout: options.timeout,
    dataset: "evals/triggers.csv",
    datasetRows: allRows.length,
    startedAt,
    piVersion: await readPiVersion(splitCommand(options.piCmd)),
    piCmd: options.piCmd,
    skillTreeHash: hashSkillTree(tree, skills),
    ...gitState(),
    baseArgs: PI_BASE_ARGS,
    extensions: options.withExtensions ? "enabled" : "disabled",
  });

  writeFileSync(join(runRoot, "report.json"), JSON.stringify(report, null, 2), "utf8");
  const markdown = renderMarkdown(report);
  writeFileSync(join(runRoot, "report.md"), markdown, "utf8");

  process.stdout.write(`\n${markdown}\n`);
  process.stdout.write(`Report: ${join(runRoot, "report.md")}\n`);
  if (options.baseline) {
    process.stdout.write(`Baseline: ${writeBaseline(options.baseline, markdown)}\n`);
  }

  if (report.totals.fail > 0 || report.totals.error > 0) process.exitCode = 1;
}

// A baseline records which skills it measured. The commit alone is a poor
// identifier, because the usual reason to run the eval is an uncommitted skill
// edit. The tree hash is taken over the SKILL.md files actually advertised.
function hashSkillTree(tree, skills) {
  const hash = createHash("sha256");
  for (const name of skills) {
    hash.update(name);
    hash.update("\0");
    hash.update(readFileSync(join(tree, name, "SKILL.md")));
    hash.update("\0");
  }
  return hash.digest("hex").slice(0, 12);
}

function gitState() {
  const run = (args) => {
    try {
      return execFileSync("git", args, { cwd: REPO_ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    } catch {
      return null;
    }
  };
  const commit = run(["rev-parse", "--short", "HEAD"]);
  if (!commit) return { commit: null, dirty: null };
  const status = run(["status", "--porcelain"]);
  return { commit, dirty: status === null ? null : status !== "" };
}

function writeBaseline(name, markdown) {
  const dir = join(HERE, "baselines");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${name}.md`);
  writeFileSync(path, markdown, "utf8");
  return path;
}

function splitCommand(value) {
  return value.trim().split(/\s+/).filter(Boolean);
}

function quoteForShell(value) {
  return /^[A-Za-z0-9_./:=@-]+$/.test(value) ? value : `'${value.replace(/'/g, "'\\''")}'`;
}

main().catch((error) => {
  process.stderr.write(`fatal: ${error.stack ?? error.message}\n`);
  process.exit(1);
});
