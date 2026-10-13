---
name: speq-plan
description: "Plan a feature or change through a clarifying interview, producing spec deltas, plan.md, and decision-log.md via planner-agent with adversarial review. Use when the user asks to plan, spec, design, or scope a new feature, a change or removal of existing behavior, a refactor, or a fix, before any implementation."
---

# Spec Planner (Orchestrator)

This skill is a thin orchestrator. It runs the clarifying interview, collects context, and delegates the planning work (spec delta authoring, test mapping, task decomposition) to `planner-agent`.

## Required Skills (for the orchestrator)

Invoke before starting:
- `/speq-cli`: spec discovery and search

`planner-agent` and `plan-reviewer` invoke their own required skills.

## Workflow

### 0. Load Project Hook (orchestrator)

Load `.speq/plan-hook.md` per this skill's `references/hook-loading.md`.

### 1. Discovery (orchestrator)

Run the speq CLI:

```bash
speq domain list
speq feature list
speq search query "<relevant terms>"
speq search query "<exact term>"   # per /speq-cli's absence check, repeated for each exact term in the request
speq decision-log show
```

Read `specs/architecture.md` if it exists.

Collect the context the interview needs: the domain and feature inventory, the search results for each exact term in the request, and the accepted ADRs. Stop there; deeper exploration belongs to `planner-agent`.

### 2. Clarifying Interview (orchestrator)

Apply the Socratic Method via `AskUserQuestion`. Never assume. Decompose the problem space with MECE partitioning:

- **Probe**: surface hidden assumptions with open-ended questions
- **Partition**: present alternative solutions as MECE options
- **Challenge**: test design tradeoffs with counterexamples

Record the answers in a concise summary for the sub-agent.

### 3. Plan Name (orchestrator)

Pattern: `<verb>-<feature-scope>[-<qualifier>]`. This table is the single owner of the verb vocabulary; `/speq-plan-pr` cites it.

| Verb | When |
|------|------|
| `add` | New feature |
| `change` | Modify existing |
| `remove` | Deprecate/delete |
| `refactor` | Restructure, same behavior |
| `fix` | Bug or spec mismatch |

### 4. Delegate to planner-agent

Spawn the planner sub-agent with everything it needs:

```
Delegate to planner-agent — Plan <plan-name>

## Plan Name
<plan-name>

## User Intent
<1-3 sentence summary of what the user wants>

## Clarifying Interview Results
<verbatim Q&A from the AskUserQuestion exchanges>

## Existing Context
<the exact `speq domain list` / `speq feature list` / `speq search query "..."` / `speq feature get` / `speq decision-log show` calls you ran, each followed by its output, plus the content of `specs/architecture.md` when it exists — name the query, not just the result>

## External Research
<any research already conducted, or "none — agent to research as needed">

## Project Hook
<if active: note ".speq/plan-hook.md — read it and apply it" — otherwise omit this section>

## Your Task
Produce spec deltas and plan.md per the `planner-agent` workflow. Tag tasks requiring deep reasoning with [expert] so the implementer orchestrator can route them to implementer-expert-agent.

Return the list of files created and the validation result.
```

### 5. Review planner-agent output (orchestrator)

When the sub-agent returns:

1. Confirm `speq plan validate <plan-name>` passed. Re-run if uncertain.
2. List all created files.
3. If the sub-agent escalated a question, resolve it with the user and respawn with the clarification.

### 6. Adversarial Plan Review (orchestrator)

Run the review loop in this skill's `references/review-loop.md`, in interactive mode. Maximum 2 rounds total. `plan-reviewer` is the diabolus advocatus; `/speq-plan-review` owns its method and taxonomy.

The loop has two interactive exits:
- **Intent gate (`INTENT > 0`):** present the Intent Fidelity findings via `AskUserQuestion` before any revision. The user accepts the plan as-is, or gives guidance and you respawn `planner-agent` manually.
- **`HUMAN` remainder:** present the findings via `AskUserQuestion`, one line of context each plus a pointer to the round file for detail. The user accepts the risk and proceeds, or gives guidance and you respawn `planner-agent` manually.

Read ADVISORY findings from the last round file that actually ran and carry them into step 7's report.

### 7. Explain next steps (orchestrator)

Print the plan's summary to the terminal per `/speq-plan-pr`'s `references/pr-body-template.md` and its terminal-print rule, composed from `plan.md` and `decision-log.md`. This step never touches git or GitHub.

Then:
- Print `ADR candidates: none`, or list the title of each `Promotes to ADR: yes` entry in `decision-log.md`. Each one is a proposed ADR, and `/speq-record` accepts it. To drop one, set it to `Promotes to ADR: no` and run this skill again
- Report ADVISORY findings from step 6, read from the round file
- If step 6's round 1 was all-`MECHANICAL` (round 2 skipped) or ran a round-2 `MECHANICAL` follow-up, name it in one line ("N mechanical findings fixed") — do not restate each one
- Tell the user to run `/speq-implement <plan-name>` to continue
- Tell the user to run `/clear` to implement with a fresh context window
- If Claude Code is in "plan mode", call `ExitPlanMode` and ask to proceed with cleared context

## Spec Hierarchy (reference)

Canonical layout: `/speq-plan`'s `references/spec-hierarchy.md`.

## Work Split (reference)

| Step | Performed by | Why |
|------|--------------|-----|
| Discovery, interview, coordination | This skill (pins Sonnet) | Conversational, tool-call heavy |
| Spec delta authoring, plan context and decision log, task decomposition | `planner-agent` sub-agent | Reasoning-heavy; a defect here compounds through implementation |
| Adversarial review, revision loop | `plan-reviewer` sub-agent | Catches intent drift, infeasibility, and ambiguity before implementation |

Each sub-agent pins its own model and effort in its frontmatter, so planning quality does not depend on the parent session's configuration.

## Anti-Patterns

| Pattern | Why Wrong |
|---------|-----------|
| Skipping the clarifying interview | Content comes from user answers, never assumptions |
| Asking the user about a `MECHANICAL` finding | Round count is not the escalation test — `Escalation: HUMAN` is; fix mechanical findings directly, no interruption |
| Running round 2 when round 1's `HUMAN` count is 0 | A round with nothing judgment-worthy left doesn't need a second adversarial pass — fix and ship |
| Persisting ADVISORY findings or looping on them | Report-only; they never gate |
