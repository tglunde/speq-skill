# Baselines

A baseline is one trigger-eval report kept on purpose, so a later run has something to compare against.

Run output lands in `evals/artifacts/`, which is gitignored. Nothing lands here by itself. You add a baseline with the runner:

```bash
mise run eval:triggers -- --model <provider/id> --baseline 2026-10-13-gpt-6-luna
```

That writes `evals/baselines/2026-10-13-gpt-6-luna.md` and prints the path.

## Why a baseline carries a tree hash

A commit sha is a poor identifier for a baseline. The usual reason to run the eval is that you just edited a skill, so the working tree is dirty and the commit does not describe what ran.

Every baseline therefore records a hash of the skill `SKILL.md` files it measured. Two baselines with the same tree hash measured the same skills, whatever the commit says.

The commit is recorded too, marked `(dirty tree)` when the working tree had uncommitted changes at run time.

## Naming

Use `<date>-<model>`, with the model slugged to lowercase and hyphens:

```
2026-10-13-gpt-6-luna.md
2026-10-13-kimi-k3.md
2026-11-02-gpt-6-luna.md
```

One baseline per model is the useful unit. A score only compares against a baseline from the same model, because a different model makes different routing choices.

## Comparing

The `## All rows` table at the end of a report is the comparison surface. Diff two baselines to see exactly which rows changed verdict:

```bash
git diff --no-index evals/baselines/2026-10-13-gpt-6-luna.md evals/baselines/2026-11-02-gpt-6-luna.md
```

Delete a baseline when its model is retired. Keep the list short.
