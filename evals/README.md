# Skill Evals

Skill evals measure whether a skill behaves as intended, not whether its text reads well.

This directory currently holds one eval: **trigger evals**. It answers a single question per dataset row. Does the named skill load when it should, and stay away when it should not?

Process, outcome, and rubric evals do not exist yet. The [Limits](#limits) section lists what is still open.

## Why trigger evals first

Pi advertises every skill by name and description, and the model chooses which one to load. A vague or overloaded description causes two failures that no other test catches.

- A miss: the user asks for something the skill covers, and the skill never loads.
- A false positive: the user asks for something else, and the wrong skill loads.

The second failure is the sharper risk in this repository. Four pairs of skills read almost the same to a model, and thirteen skills carry descriptions written for other agents rather than for users.

## Prerequisites

- `pi` on `PATH`, with credentials for the model you pass to `--model`.
- Node.js 22 or newer. The repository targets Node 26.
- A built payload. Run `./scripts/plugin/build.sh`, or pass `--set source`.

### Credentials

The runner spawns `pi` once per run and inherits the environment it was started from. Two setups work.

- Credentials are already exported in your shell. Plain `pi` works, and no extra flag is needed.
- Pi is launched through a credential broker. Run the whole runner through the broker, or point `--pi-cmd` at it:

```bash
fnox proxy run -- node evals/run-trigger-evals.mjs --model <provider/id>

node evals/run-trigger-evals.mjs --model <provider/id> --pi-cmd "fnox proxy run -- pi"
```

When `pi` cannot reach a provider, every run is reported as `ERROR` with the provider message in the trace's `.stderr.txt` file. That is a setup problem, not a trigger defect.

## Quick start

Verify the grader without spending a prompt:

```bash
node --test evals/test/
```

Run four rows to confirm the setup end to end:

```bash
node evals/run-trigger-evals.mjs \
  --model <provider/id> \
  --only e03,b01,n01,p01 \
  --runs 1
```

Run the full dataset:

```bash
node evals/run-trigger-evals.mjs --model <provider/id>
```

The runner writes every trace to `evals/artifacts/<timestamp>/`, plus `report.md` and `report.json`. It exits non-zero when any row fails or cannot run.

## Options

| Option | Default | Purpose |
|---|---|---|
| `--model <pattern>` | required | The Pi model. Every row uses the same model, so a model swap does not look like a trigger regression. |
| `--provider <name>` | unset | Restricts `--model` lookup to one provider. |
| `--thinking <level>` | unset | Sets the reasoning level. |
| `--set <payload\|source>` | `payload` | Which skill tree to advertise. |
| `--runs <n>` | `3` | Runs per row. The majority decides. |
| `--timeout <seconds>` | `180` | Per-run wall clock limit. |
| `--concurrency <n>` | `1` | Rows in flight. |
| `--only <id,id>` | all | Runs a subset of rows. |
| `--class <c,c>` | all | Runs a subset of classes. |
| `--list` | | Prints the dataset and exits. |
| `--dry-run` | | Prints the Pi command for each row and exits. |
| `--pi-cmd <command>` | `pi` | How to launch Pi. Split on spaces. |
| `--baseline <name>` | unset | Copies the report to `evals/baselines/<name>.md`. |
| `--with-extensions` | off | Re-enables Pi extensions. |
| `--keep-workspace` | off | Keeps the throwaway workspaces for inspection. |
| `--extra-arg <arg>` | | Passes an extra argument to Pi. Repeatable. |

## How a skill counts as loaded

Pi has no skill-invocation event. It advertises each skill by name, description, and path in the system prompt, then loads the full instructions only when the model reads the file. A skill therefore counts as loaded when a tool call touches a file inside that skill's directory.

Three traps shape the matcher, and `evals/test/grade.test.mjs` pins all three.

1. The system prompt already contains every skill path. Scanning the whole trace would report every advertised skill as loaded, so the matcher reads tool-call arguments only.
2. `speq-plan` is a prefix of `speq-plan-pr`. The matcher anchors on the directory boundary and requires a file below it. Listing a skill directory is not a load.
3. A load is not a choice. The orchestrator skills are required by their own text to read sibling skills, so `speq-plan-pr` reads `/skill:speq-plan`'s references and `speq-code-review` reads `/skill:speq-code-guardrails`. Those reads are delegations from the entry point, not a second trigger.

### Loaded versus entry

The two expectations in the dataset ask different questions, and each is scored on the measure that answers it.

- A `should_trigger=true` row asks whether the skill's instructions entered context at all. It is scored on the loaded set.
- A `should_trigger=false` row asks whether the model *chose* that skill. It is scored on the entry skill: the first skill file the run read, in stream order. A skill the entry point reads itself is a documented delegation, not a mis-trigger.

Both values are reported per row, so a run that entered correctly and then delegated still shows the full loaded set.

## The dataset

`evals/triggers.csv` holds one row per case: `id`, `class`, `skill`, `should_trigger`, `prompt`, `rationale`.

| Class | Meaning | Rows |
|---|---|---|
| `entry` | A user prompt must load the named skill. | 11 |
| `boundary` | A user prompt must not *choose* the named skill, because a sibling owns it. | 14 |
| `internal-negative` | A user prompt must not choose the named agent-internal skill. | 12 |
| `internal-positive` | An agent instruction must load the named agent-internal skill. | 14 |

Two invariants hold, and the test suite enforces both. Every skill in the payload tree appears in the dataset. Every skill appears with at least one `should_trigger=true` row and at least one `should_trigger=false` row.

Some rows carry a rationale that starts with `Debatable`. Those expectations are a design intent rather than a hard rule. Read the actual result before changing the skill.

## Reading the report

The report leads with the score, then breaks it down by class.

- **PASS** means the majority of runs matched the expectation.
- **FAIL** means the majority did not.
- **ERROR** means the runs never reached the model. A missing API key produces this, not a trigger defect.
- **Not unanimous** lists rows that split across runs. A row that passes 2 of 3 is a weaker signal than one that passes 3 of 3, and it is the first place to look when a score moves.

Each row also reports the entry skill and the skills it loaded beyond the one under test. A run that loads the right skill plus four others is not the same result as a run that loads only the right one. On a failure the report prints both lines, so a wrong entry point reads differently from a correct entry point that delegated.

## Baselines

Run output is gitignored, because traces are bulk and every invocation writes a new timestamped directory. Promote the runs worth keeping into `evals/baselines/`:

```bash
mise run eval:triggers -- --model <provider/id> --baseline 2026-10-13-gpt-6-luna
```

A baseline records a hash of the skill files it measured, so two baselines with the same hash measured the same skills even when the working tree was dirty. Diff two baselines to see which rows changed verdict. See [baselines/README.md](baselines/README.md).

## Cost

The full dataset is 51 rows. At the default of 3 runs per row that is 153 Pi runs. Start with `--only` on a handful of rows, then widen.

## Limits

- Only trigger behavior is measured. Nothing yet checks whether a run followed the intended steps, produced the intended files, or matched the prose conventions.
- The eval measures skill selection, not skill execution. MCP servers and extensions are disabled so that selection is the only variable.
- A row is scored on the skill named in the dataset. A run that loads the wrong sibling and still completes the task counts as a failure, which is the intent.
- Trigger decisions are stochastic. Three runs detect a flaky row but do not measure its rate. Raise `--runs` when you are chasing one.
