# Spec Hierarchy

Canonical layout of the `specs/` tree. Shared by `speq-plan`, `speq-plan-pr`, and `speq-implement-pr`.

```
specs/
├── <domain>/<feature>/spec.md            # Permanent (after record)
├── architecture.md                       # Permanent, changed by the recorder applying the plan's architecture delta
├── _plans/<plan-name>/                   # Active until recorded; committed whole except notes/
│   ├── plan.md                           # Created by planner-agent
│   ├── decision-log.md                   # Created by planner-agent
│   ├── architecture.md                   # Architecture delta, present only when the plan changes the architecture
│   ├── open-questions.md                 # Present only while blocked
│   ├── tasks.md                          # ## PR Lifecycle checkpoint, then the WBS filled by speq-implement
│   ├── review-findings.md                # Created by code-reviewer
│   ├── review/round-N.md                 # Created by plan-reviewer
│   ├── notes/<group-letter>.md           # Rotation hand-off notes, local, never committed
│   └── verification-report.md            # Created by speq-implement
└── _recorded/NNN-<plan-name>/            # Archived by speq-record (gitignored by default)
```
