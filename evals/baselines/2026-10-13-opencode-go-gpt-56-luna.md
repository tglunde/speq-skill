# Trigger Eval Report

**37 of 49 rows pass (76%).** 12 fail, 4 are not unanimous, 0 could not run.

## Run

- Model: `opencode-go/gpt-5.6-luna`
- Skill set: `payload` (20 skills, dist/marketplace/pi/skills)
- Runs per row: 3
- Dataset: evals/triggers.csv (49 rows)
- Started: 2026-10-13T19:48:15.206Z
- Skill tree hash: `eef983196e74`
- Commit: `6ed2a2e`
- Pi version: 1.1.0

## By class

| Class | Rows | Pass | Fail | Flaky | Error | Pass rate |
|---|---|---|---|---|---|---|
| boundary | 15 | 8 | 7 | 1 | 0 | 53% |
| entry | 10 | 10 | 0 | 0 | 0 | 100% |
| internal-negative | 11 | 6 | 5 | 3 | 0 | 55% |
| internal-positive | 13 | 13 | 0 | 0 | 0 | 100% |

## Failures

### b01: speq-plan should not trigger

> Plan the billing export feature and open a draft PR on a feat branch so the team can review it in CI.

- Passed 0 of 3 runs
- Loaded: speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-git-operations, speq-plan, speq-plan-pr, speq-plan-review, speq-planning, speq-writing-guardrails
- Why this expectation: speq-plan-pr owns the headless PR path. The interactive planner is the wrong entry here.

### b03: speq-implement should not trigger

> Take the plan on feat/add-dark-mode all the way to a ready PR. Implement it, run the tests, record, and push.

- Passed 0 of 3 runs
- Loaded: speq-adr-rules, speq-cli, speq-code-guardrails, speq-code-review, speq-code-tools, speq-design-philosophy, speq-git-operations, speq-implement, speq-implement-pr, speq-plan, speq-plan-pr, speq-record, speq-spec-merge, speq-writing-guardrails
- Why this expectation: An end-to-end branch-to-PR run is speq-implement-pr.

### b05: speq-record should not trigger

> The plan is verified. Merge it into the permanent spec library and archive the plan directory.

- Passed 0 of 3 runs
- Loaded: speq-adr-rules, speq-cli, speq-record, speq-spec-merge, speq-writing-guardrails
- Why this expectation: The user-facing merge request is speq-record, not the internal delta-merge procedure.

### b06: speq-spec-merge should not trigger

> Apply the DELTA markers from the plan spec into the permanent spec at specs/calculator/history/spec.md.

- Passed 0 of 3 runs
- Loaded: speq-spec-merge, speq-writing-guardrails
- Why this expectation: Debatable. This names the internal merge procedure, but the user-facing entry is speq-record. Watch the actual result rather than treating it as a hard failure.

### b10: speq-code-guardrails should not trigger

> Review this diff and report your findings in the usual format.

- Passed 0 of 3 runs
- Loaded: speq-cli, speq-code-guardrails, speq-code-review, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-writing-guardrails
- Why this expectation: The review taxonomy, not the TDD cycle.

### b11: speq-design-philosophy should not trigger

> Implement the retry logic test-first following the project guardrails.

- Passed 0 of 3 runs
- Loaded: speq-cli, speq-code-guardrails, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-implement
- Why this expectation: Debatable. speq-design-philosophy says it is triggered before any implementation work, but the design intent is that speq-implement loads it internally.

### b14: speq-plan should not trigger

> Something is wrong with our specs. Check the whole library for structural problems.

- Passed 0 of 3 runs
- Loaded: speq-audit, speq-cli, speq-plan, speq-writing-guardrails
- Why this expectation: A library-wide structural check is speq-audit.

### n02: speq-plan-review should not trigger

> Review the plan you just wrote and tell me what is weak about it.

- Passed 0 of 3 runs
- Loaded: speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-plan, speq-plan-review, speq-planning, speq-writing-guardrails
- Why this expectation: Adversarial review is a phase inside speq-plan. speq-plan-review is plan-reviewer internal.

### n04: speq-cli should not trigger

> Search the spec library for anything about backoff.

- Passed 0 of 3 runs
- Loaded: speq-cli
- Why this expectation: Debatable. The speq-cli skill is documented as invoked by orchestrators and sub-agents, but a bare search request is a plausible match.

### n05: speq-adr-rules should not trigger

> Write down the decision we just made about the retry strategy.

- Passed 0 of 3 runs
- Loaded: speq-adr-rules, speq-cli, speq-writing-guardrails
- Why this expectation: Decision capture happens inside speq-plan or speq-record. speq-adr-rules holds the ADR test.

### n06: speq-writing-guardrails should not trigger

> Rewrite the README so it reads better.

- Passed 1 of 3 runs
- Loaded: speq-writing-guardrails
- Why this expectation: The prose rules cover speq artifacts and GitHub text, not general editing.

### n09: speq-design-philosophy should not trigger

> What does information hiding mean?

- Passed 1 of 3 runs
- Loaded: speq-design-philosophy
- Why this expectation: An informational question about a concept, not design work on this codebase.

## Not unanimous

| Row | Skill | Expected | Passes | Loaded |
|---|---|---|---|---|
| b07 | speq-git-operations | no trigger | 2/3 | speq-git-discipline, speq-git-operations |
| n01 | speq-planning | no trigger | 2/3 | speq-adr-rules, speq-cli, speq-design-philosophy, speq-plan, speq-planning, speq-writing-guardrails |
| n06 | speq-writing-guardrails | no trigger | 1/3 | speq-writing-guardrails |
| n09 | speq-design-philosophy | no trigger | 1/3 | speq-design-philosophy |

## All rows

| Row | Class | Skill | Expected | Verdict | Passes | Also loaded |
|---|---|---|---|---|---|---|
| b01 | boundary | speq-plan | no trigger | FAIL | 0/3 | speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-git-operations, speq-plan-pr, speq-plan-review, speq-planning, speq-writing-guardrails |
| b02 | boundary | speq-plan-pr | no trigger | PASS | 3/3 | speq-cli, speq-plan |
| b03 | boundary | speq-implement | no trigger | FAIL | 0/3 | speq-adr-rules, speq-cli, speq-code-guardrails, speq-code-review, speq-code-tools, speq-design-philosophy, speq-git-operations, speq-implement-pr, speq-plan, speq-plan-pr, speq-record, speq-spec-merge, speq-writing-guardrails |
| b04 | boundary | speq-implement-pr | no trigger | PASS | 3/3 | speq-cli, speq-code-guardrails, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-implement, speq-writing-guardrails |
| b05 | boundary | speq-record | no trigger | FAIL | 0/3 | speq-adr-rules, speq-cli, speq-spec-merge, speq-writing-guardrails |
| b06 | boundary | speq-spec-merge | no trigger | FAIL | 0/3 | speq-writing-guardrails |
| b07 | boundary | speq-git-operations | no trigger | PASS | 2/3 | speq-git-discipline |
| b08 | boundary | speq-git-discipline | no trigger | PASS | 3/3 | speq-cli, speq-git-operations, speq-implement, speq-implement-pr, speq-plan, speq-plan-pr, speq-record, speq-writing-guardrails |
| b09 | boundary | speq-code-review | no trigger | PASS | 3/3 | speq-code-guardrails |
| b10 | boundary | speq-code-guardrails | no trigger | FAIL | 0/3 | speq-cli, speq-code-review, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-writing-guardrails |
| b11 | boundary | speq-design-philosophy | no trigger | FAIL | 0/3 | speq-cli, speq-code-guardrails, speq-code-tools, speq-git-discipline, speq-implement |
| b12 | boundary | speq-plan | no trigger | PASS | 3/3 | speq-cli, speq-ext-research, speq-mission, speq-writing-guardrails |
| b13 | boundary | speq-mission | no trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-design-philosophy, speq-plan, speq-planning, speq-writing-guardrails |
| b14 | boundary | speq-plan | no trigger | FAIL | 0/3 | speq-audit, speq-cli, speq-writing-guardrails |
| b15 | boundary | speq-audit | no trigger | PASS | 3/3 | speq-cli, speq-code-guardrails, speq-code-review, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-writing-guardrails |
| e01 | entry | speq-mission | trigger | PASS | 3/3 | speq-cli, speq-ext-research, speq-plan, speq-writing-guardrails |
| e02 | entry | speq-mission | trigger | PASS | 3/3 | speq-audit, speq-cli, speq-ext-research, speq-plan, speq-writing-guardrails |
| e03 | entry | speq-plan | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-plan-review, speq-planning, speq-writing-guardrails |
| e04 | entry | speq-plan | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-design-philosophy, speq-planning, speq-writing-guardrails |
| e05 | entry | speq-implement | trigger | PASS | 3/3 | speq-cli, speq-code-guardrails, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-writing-guardrails |
| e06 | entry | speq-record | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-plan, speq-spec-merge, speq-writing-guardrails |
| e07 | entry | speq-audit | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-plan, speq-writing-guardrails |
| e08 | entry | speq-plan-pr | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-git-operations, speq-plan, speq-plan-review, speq-planning, speq-writing-guardrails |
| e09 | entry | speq-implement-pr | trigger | PASS | 3/3 | speq-cli, speq-code-guardrails, speq-code-tools, speq-design-philosophy, speq-git-operations, speq-implement, speq-plan, speq-record, speq-spec-merge, speq-writing-guardrails |
| e10 | entry | speq-audit | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-plan, speq-writing-guardrails |
| n01 | internal-negative | speq-planning | no trigger | PASS | 2/3 | speq-adr-rules, speq-cli, speq-design-philosophy, speq-plan, speq-writing-guardrails |
| n02 | internal-negative | speq-plan-review | no trigger | FAIL | 0/3 | speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-plan, speq-planning, speq-writing-guardrails |
| n03 | internal-negative | speq-code-tools | no trigger | PASS | 3/3 |  |
| n04 | internal-negative | speq-cli | no trigger | FAIL | 0/3 |  |
| n05 | internal-negative | speq-adr-rules | no trigger | FAIL | 0/3 | speq-cli, speq-writing-guardrails |
| n06 | internal-negative | speq-writing-guardrails | no trigger | FAIL | 1/3 |  |
| n07 | internal-negative | speq-git-discipline | no trigger | PASS | 3/3 |  |
| n08 | internal-negative | speq-ext-research | no trigger | PASS | 3/3 |  |
| n09 | internal-negative | speq-design-philosophy | no trigger | FAIL | 1/3 |  |
| n10 | internal-negative | speq-code-review | no trigger | PASS | 3/3 |  |
| n11 | internal-negative | speq-spec-merge | no trigger | PASS | 3/3 | speq-git-operations |
| p01 | internal-positive | speq-spec-merge | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-git-discipline, speq-plan, speq-record, speq-writing-guardrails |
| p02 | internal-positive | speq-plan-review | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-plan, speq-planning, speq-writing-guardrails |
| p03 | internal-positive | speq-adr-rules | trigger | PASS | 3/3 |  |
| p04 | internal-positive | speq-writing-guardrails | trigger | PASS | 3/3 | speq-plan, speq-planning |
| p05 | internal-positive | speq-code-guardrails | trigger | PASS | 3/3 | speq-cli, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-implement |
| p06 | internal-positive | speq-code-tools | trigger | PASS | 3/3 |  |
| p07 | internal-positive | speq-cli | trigger | PASS | 3/3 |  |
| p08 | internal-positive | speq-code-review | trigger | PASS | 3/3 | speq-cli, speq-code-guardrails, speq-code-tools, speq-design-philosophy, speq-git-discipline, speq-writing-guardrails |
| p09 | internal-positive | speq-design-philosophy | trigger | PASS | 3/3 | speq-code-guardrails, speq-code-tools |
| p10 | internal-positive | speq-ext-research | trigger | PASS | 3/3 |  |
| p11 | internal-positive | speq-git-operations | trigger | PASS | 3/3 |  |
| p12 | internal-positive | speq-planning | trigger | PASS | 3/3 | speq-adr-rules, speq-cli, speq-design-philosophy, speq-plan, speq-writing-guardrails |
| p13 | internal-positive | speq-git-discipline | trigger | PASS | 3/3 |  |
