# Adversarial Plan Review Loop

Shared by the `speq-plan` and `speq-plan-pr` orchestrators. The two differ only in how a human is asked and how the plan ships; the loop itself is identical. This file owns that loop. The `speq-plan-review` skill owns the reviewer's method, taxonomy, severity, and escalation classes.

## Round 1

Spawn `plan-reviewer` with this brief:

```
Delegate to plan-reviewer — Review <plan-name> (round 1)

## Plan Name
<plan-name>

## User Intent
<verbatim original request>

## Clarifying Interview Results
<verbatim Q&A, or the headless intent text in its place>

## Plan Artifacts
plan.md, decision-log.md, every specs/_plans/<plan-name>/**/spec.md delta, and specs/_plans/<plan-name>/architecture.md when present

## Project Hook
<if active: note "<active hook path> — read it and apply it" — otherwise omit this section>
```

It writes `specs/_plans/<plan-name>/review/round-1.md` and returns exactly one line:

```
PLAN REVIEW round 1: BLOCKERS: <n>, ADVISORY: <n>, INTENT: <n>, HUMAN: <n> — <path>
```

`INTENT` counts the Intent Fidelity BLOCKERs alone. `HUMAN` counts every BLOCKER tagged `Escalation: HUMAN` (Intent Fidelity included). The rest are `MECHANICAL`, derivable as `BLOCKERS - HUMAN`.

## Intent gate

If `INTENT > 0`, the reviewer holds that the plan solves a different problem than the one asked. Read the Intent Fidelity findings from the round file. A substituted or dropped ask always needs the requester:

- Interactive: present the findings with `AskUserQuestion` before any revision. The user accepts the plan as-is, or gives guidance and you respawn `planner-agent` manually.
- Headless: fold the findings into the `OPEN QUESTIONS:` branch and stop.

## Revision pass

If `INTENT == 0` and BLOCKER findings exist, respawn `planner-agent` with the path to `review/round-1.md`. Instruct it to read the BLOCKER findings from that file, execute each `Fix:` line, log each resolved blocker as a `[plan-review]`-prefixed `## Review Findings` entry in `decision-log.md`, re-run `speq plan validate`, and return its per-finding `Resolved:`/`Could not resolve:` report per the `speq-planning` skill's Revision Mode.

## Plan Size

Compute this before a round-2 respawn. The plan is `small` when all three hold: the plan-name's verb (per the verb table in the `speq-plan` skill) is `fix`; `decision-log.md`'s `## Design Decisions` section is empty; the plan directory has no `architecture.md`. Otherwise it is `full`.

## Round 2

Round 2 runs only if round 1's `HUMAN` count was greater than 0. A round 1 with `HUMAN: 0` means every BLOCKER was `MECHANICAL`: the reviewer already judged that none needed adversarial re-checking, only a fix. Skip to the ship decision below.

When `HUMAN > 0`, respawn `plan-reviewer` for round 2 with the path to `review/round-1.md` plus `Plan Size: small | full`, so it confirms each round-1 BLOCKER is resolved before checking for new ones (or, on `small`, confirms and stops there). Do not run a third adversarial round, even if round 2 raises new BLOCKERs.

## Remaining blockers after round 2

Split by `Escalation`:

- **`MECHANICAL` remainder:** respawn `planner-agent` once more with the still-open `MECHANICAL` findings from `review/round-2.md`, same Revision Mode format. Do not interrupt the user for these unless one comes back `Could not resolve:` or `speq plan validate` fails.
- **`HUMAN` remainder** (plus any `MECHANICAL` finding a fix pass could not close): read those findings and route by mode:
  - Interactive: one line of context each via `AskUserQuestion`, plus a pointer to the round file for detail. The user accepts the risk and proceeds, or gives guidance and you respawn `planner-agent` manually.
  - Headless: fold them into the `OPEN QUESTIONS:` branch.

## Ship decision

The loop returns a clean result only when `speq plan validate` passed and every finding came back `Resolved:`. A `MECHANICAL` tag means the reviewer judged it not to need human judgment; it does not guarantee the first retry fixes it. Any `Could not resolve:` line, or a failed re-validate, is not clean and routes to the mode-specific outcome above.

## ADVISORY findings

ADVISORY findings never loop and are never persisted. Read them from the last round file that actually ran: round 1's when round 2 was skipped entirely (`HUMAN: 0`) or ran confirm-only (`Plan Size: small`); round 2's otherwise. Carry them into the terminal report.
