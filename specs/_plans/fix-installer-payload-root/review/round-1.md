# Plan Review Findings: fix-installer-payload-root (round 1)

## Summary
- Axes checked: 6/6
- Total findings: 3 (Blockers: 0, Advisory: 3)
- Intent Fidelity blockers: 0
- Human-escalation blockers: 0

## Intent Fidelity
[no objection — axis checked: plan.md Requirements rows map 1:1 to the interview decisions. Interview A1 asks for one payload root inside `install_pi_agents`, `${MARKETPLACE_DIR:-$HOME/.speq-skill}` in both installer scripts, and the pre-source assignment in `scripts/local-install.sh`; tasks 1.1, 1.2, and 1.3 implement exactly those three operations. Interview A3 asks for a split-root case in `tests/pi_model_overrides.rs` with no end-to-end `local-install.sh` test; task 1.4 does this and the "Regression proof" requirement states the exclusion. Interview A2's precondition is verified in the repository: `distribution/model-routing` and `distribution/pi-model-overrides` are permanent under `specs/`, the plan is archived at `specs/_recorded/002-add-model-routing-table`, and ADR `one-routing-table-owns-model-and-effort` is `Status: Accepted` in `speq decision-log show`. No scope creep: the uninstaller caller-root test (task 1.5) traces to A1 and to the NEW uninstaller scenario, and every `## Dead Code Removal` entry is a direct consequence of tasks 1.1 and 1.3.]

## Feasibility

#### [UNSTATED_ASSUMPTION] ADVISORY
- Location: decision-log.md § Design Decisions [1] and [2]; install.sh line 11
- Issue: the plan binds only `PI_OVERRIDES_ARTIFACT` at function time. `CODEX_MARKETPLACE_ROOT="$MARKETPLACE_DIR/codex"` (install.sh line 11, consumed by `register_codex_plugin` at lines 59 to 75) stays source-time derived. After task 1.3, every in-repo flow sets `MARKETPLACE_DIR` before sourcing, so no live flow splits; `scripts/local-install.sh` even re-derives its own root at line 19. But a caller that reassigns `MARKETPLACE_DIR` after sourcing still gets a stale Codex root while the Pi paths follow the new root. The plan never states this invariant: `MARKETPLACE_DIR` must be final before `install.sh` is sourced for every other source-time derivation to stay consistent.
- Fix: Add one sentence to the `Consequences` line of decision-log entry [2]: source-time derived values such as `CODEX_MARKETPLACE_ROOT` assume `MARKETPLACE_DIR` is set before `install.sh` is sourced; assignments after sourcing are not supported.

#### [NFR_IGNORED] ADVISORY
- Location: plan.md § Requirements ("Caller override"); uninstall.sh lines 390-391; install.sh lines 660 and 736 (`merge_tree`)
- Issue: once `uninstall.sh` honors a caller-provided `MARKETPLACE_DIR`, step 8 runs `rm -rf` on whatever the caller supplied. A value of `$HOME`, `/`, or a populated project directory destroys operator data. The current script removes only the constant `$HOME/.speq-skill`, so this change introduces the destructive surface. The installer's `merge_tree` step likewise writes into an arbitrary caller directory. Interview A1 mandates the caller-override capability itself, so this is not a scope question; it is a missing guardrail decision.
- Fix: Either add a guard to `uninstall.sh` that refuses dangerously broad targets (for example, reject `/` and `$HOME`, or require a marker file from a prior install inside the target before removal) and note it in decision-log entry [2], or record in entry [2]'s `Consequences` line that callers accept full responsibility for the target directory and no guard is provided.

## Requirement Quality
[no objection — axis checked: the CHANGED Background is a superset of the recorded `specs/distribution/pi-model-overrides/spec.md` Background (first seven bullets identical, two appended), so no scenario is silently altered. Both new Background bullets have dependent scenarios: the one-root rule backs "Installer uses one payload root for Pi agents and overrides", and the caller-may-provide rule backs both NEW scenarios; the default-root half is depended on by all twelve existing scenarios, which name no root. Both NEW scenarios are testable with concrete pass/fail assertions and map to named tests in the plan.md Verification table. No contradiction with any recorded spec or scenario: `speq feature validate` passes on all features, `speq plan validate fix-installer-payload-root` passes, and semantic searches for "MARKETPLACE_DIR payload root installer" and "uninstaller removes marketplace directory" return no competing scenario. No `REQUIREMENT_CONFLICT` with the recorded `distribution/model-routing` spec, whose Background scopes the routing table to build-input only.]

## Task Breakdown
[no objection — axis checked: every delta element has an implementing task (Background bullets and installer scenario -> 1.1 and 1.4; uninstaller scenario -> 1.2 and 1.5; local-install ordering -> 1.3) and every task implements something in scope. Tasks are single, verifiable edits. The one Parallelization group shares one spec delta and the installer modules and one shared harness, so the single vertical slice is coherent. Verification task 2.1 covers every row of the plan.md Checklist and Scenario Coverage table, including the negative check that the new test fails against the old wiring.]

## Design Depth
[no objection — axis checked: the change adds no new module, interface, or boundary, so the diagnostic table does not apply. Decision [1] removes a temporal coupling: the payload-root decision previously leaked across source time (`PI_OVERRIDES_ARTIFACT`, install.sh line 31) and call time (`$MARKETPLACE_DIR/pi/agents`, install.sh line 525); the fix gives one owner at one time. All four decision-log entries carry `Promotes to ADR: no`, which satisfies `/speq-adr-rules` rules 1 and 3: this plan is a one-off bug fix, and its defaults handling, test placement, and conformance entries are local. Entry [4] carries `Architecture: no change: specs/architecture.md describes the Rust CLI...`, which matches the verified repository fact that `specs/architecture.md` has no installer component or data flow, so no architecture delta is owed. Entry [4] conforms to accepted ADR `one-routing-table-owns-model-and-effort` (read via `speq decision-log show`) rather than contradicting it, so no superseding entry is needed.]

## Prose Quality

#### [PROSE_UNCLEAR] ADVISORY
- Location: plan.md § Implementation Tasks, task 1.4
- Issue: one sentence packs two distinct bash invocation shapes together: "verifies a pre-source caller override and then sources `install.sh` with an old default root, switches to the installing root before calling `install_pi_agents`, and asserts...". Read as a single flow, the test would set `MARKETPLACE_DIR` pre-source, then overwrite it itself when it "switches to the installing root", and the "Caller override" preservation requirement would never be exercised, because nothing derived at source time is asserted afterward. The intended coverage is two invocations in the one test: a pre-source override run and a post-source switch run.
- Fix: Rewrite task 1.4 as two numbered clauses, one per invocation: (a) export `MARKETPLACE_DIR=<caller-root>`, source `install.sh` with a populated `$HOME/.speq-skill` default root, call `install_pi_agents`, assert the caller root's agent and pin win; (b) source `install.sh` with `MARKETPLACE_DIR` unset and a populated default root, assign `MARKETPLACE_DIR=<installing-root>`, call `install_pi_agents`, assert the installing root's agent and pin win and the default root's pin is ignored.
