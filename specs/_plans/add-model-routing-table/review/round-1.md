# Plan Review Findings: add-model-routing-table (round 1)

## Summary
- Axes checked: 6/6
- Total findings: 9 (Blockers: 2, Advisory: 7)
- Intent Fidelity blockers: 0
- Human-escalation blockers: 0

## Intent Fidelity
[no objection: axis checked. The plan delivers the turn-2 ask ("a yaml with agent name/md-file/model-id/thinking-effort that gets installed into the target harnesses") for all three harnesses: `claude:` and `codex:` values are injected into the emitted plugin trees at build time, and `pi.model` values reach `~/.pi/agent/settings.json` through the generated `pi/model-overrides.json` and the installer. The all-null `pi.model` column matches the Q1 preview the user selected, and the repository-tree routing loss is the Q2 answer the user chose and is stated in plan.md § Impact. No ask is dropped or substituted.]

## Feasibility

#### [UNSTATED_ASSUMPTION] ADVISORY
- Location: plan.md § Implementation Tasks 4.2
- Issue: task 4.2 says "source `install.sh` and run `uninstall.sh` with `HOME` pointed at a temporary directory". `uninstall.sh` ends with an unconditional `main "$@"` and has no `BASH_SOURCE` guard, so sourcing it runs the full uninstaller. Running it as a subprocess with a temporary `HOME` still executes steps 1 and 2, which call the real `claude` CLI and can uninstall the operator's installed plugin. The plan names no isolation mechanism. The existing precedent in `tests/install_mcp_servers.rs` pins `PATH` to a fake bin directory plus `/usr/bin:/bin` only, so a real tool can never leak in.
- Fix: name the isolation strategy in task 4.2: run `uninstall.sh` as a subprocess with `HOME` in a temporary directory and `PATH` restricted to a fake bin directory plus `/usr/bin:/bin` (with fakes for `claude` and `codex`), or add a `BASH_SOURCE` guard to `uninstall.sh` and source `remove_pi_agents` directly.

## Requirement Quality

#### [COMPLETENESS_GAP] BLOCKER
- Location: `distribution/pi-model-overrides/spec.md` § Scenarios; plan.md § Implementation Tasks 2.1
- Issue: the feature's main scenario assumes "the operator's `settings.json` exists", and neither the delta nor task 2.1 covers an absent file, an invalid JSON document, or a write failure. When a row pins a model and `~/.pi/agent/settings.json` does not exist, the implementer must choose between creating it and silently doing nothing; the plan does not decide. An invalid document makes `JSON::PP` die, which under `set -e` aborts the install after `install_pi_agents` has already replaced `$PI_AGENTS_DIR`. A direct write can also leave a truncated file on a mid-write failure; the "never a partial write" requirement covers only a missing module.
- Fix: add scenarios to `distribution/pi-model-overrides/spec.md` for settings.json absent while the payload pins a model, settings.json invalid, and a failed write. Require the installer to create the file when it has at least one pinned model, to warn and leave the file untouched when the document is invalid, and to write through a temporary file plus rename so a failure leaves the original byte-identical. State the uninstaller's behavior for the same three cases.
- Escalation: MECHANICAL

#### [REQUIREMENT_CONFLICT] BLOCKER
- Location: plan.md § Implementation Tasks 2.1 vs decision-log.md § Design Decisions [6]
- Issue: task 2.1 says "When the artifact is missing or empty, touch nothing". Decision [6] says "Reinstall reconciles. A name in the old marker that the new artifact no longer pins is removed." The two conflict whenever a reinstall follows a payload that pinned models and the new payload pins none: the agents directory is still replaced, so the old marker is destroyed, the settings entries are not removed, and the uninstaller can never find them again. The delta's scenario "Installer writes nothing when no model is pinned" also forbids the reconcile write without qualifying that no previous install recorded overrides.
- Fix: rewrite task 2.1 so every install path reconciles: when the artifact is missing or empty, remove the previous marker's names from `settings.json` and rewrite the marker to the new set. Keep the "MUST NOT modify settings.json" guarantee for the case with no previous marker only. Add a scenario "Installer removes overrides the previous install recorded but the current payload no longer pins", and add "and no previous install recorded overrides" to the GIVEN of the no-pins scenario.
- Escalation: MECHANICAL

#### [AMBIGUOUS_REQUIREMENT] ADVISORY
- Location: plan.md § Requirements "Routing table subset"; plan.md § Implementation Tasks 1.2; `distribution/model-routing/spec.md` § Scenarios
- Issue: task 1.2 requires a row for each of 20 skills, but only 6 skills carry a model today. Neither the plan nor the delta states the `claude:` and `codex:` encoding for the other 14, or what the build does with an empty harness map. The subset allows `{}` and treats a missing map as an error, so `{}` must be the "inherited" encoding, yet no scenario covers it. The plan also does not say where the 14 utility skills' `note:` values come from; the current docs aggregate them into one "Utility skills" row.
- Fix: state in plan.md § Requirements that an empty harness map injects nothing and renders as `inherited`. State in task 1.2 that the 14 utility skills get `claude: {}` and `codex: {}` with a shared note value. Add one scenario to `distribution/model-routing/spec.md` covering a row whose harness map is empty.

#### [COMPLETENESS_GAP] ADVISORY
- Location: plan.md § Implementation Tasks 3.1; `docs/model-routing.md` § "Pin the Pi models"
- Issue: task 3.1 regenerates the three tables and says "the Pi section explains the installer's override behavior", but it never says whether the hand-written "Pin the Pi models" JSON snippet survives. The docs check compares only the marked table blocks, so a stale snippet cannot fail it. The snippet tells operators to edit `settings.json` directly, which conflicts with the plan's "the table is the single source" prose.
- Fix: state the snippet's fate in task 3.1: replace it with table-driven instructions plus a short manual-override fallback, or keep it explicitly as the fallback and say so in the prose. Put the chosen text inside the checked region if it is generated.

#### [COMPLETENESS_GAP] ADVISORY
- Location: plan.md § Requirements row "No new dependency"; plan.md § Implementation Tasks 2.2
- Issue: the requirement names `build.sh` and `install.sh` and omits `uninstall.sh`, which task 2.2 also changes. Task 2.2 says the uninstaller uses "the same perl and `JSON::PP` helper with the same fallback", but the installer's fallback is "warn and print the JSON to add", which has no meaning for a removal, and `uninstall.sh` already carries python3 and node JSON helpers for the Codex legacy file.
- Fix: extend the requirement to `uninstall.sh`, and specify its perl-missing behavior: warn, list the `subagents.agentOverrides` entries to remove manually, and exit 0 without touching the file. Say whether it reuses the existing python3/node fallback or keeps perl only.

#### [COMPLETENESS_GAP] ADVISORY
- Location: plan.md § Impact; plan.md § Implementation Tasks 1.2
- Issue: the Impact states that the in-repo `.claude/agents/*.md` and skill files "run on the session model" after the change, but no task writes that consequence into a durable document. Task 1.2 adds one CLAUDE.md line naming the table as the only routing source, which does not tell a contributor that repository-tree invocations lose their pins or that the new guard enforces that state.
- Fix: extend task 1.2's CLAUDE.md line to state that the repository-tree copies carry no routing and inherit the session model, and that `guard_source_frontmatter` rejects a re-added `model:`, `effort:`, or `thinking:` line.

## Task Breakdown

#### [COMPLETENESS_GAP] ADVISORY
- Location: plan.md § Dead Code Removal
- Issue: the listed locations match the real file (`set_codex_skill_model` at `scripts/plugin/build.sh:111`, `PI_AGENT_NAMES` at 143, `transform_pi_markdown` deletions at 244-245, `transform_pi_agent` effort rename at 261, `set_codex_agent_model` at 323, the routing summary at 591), but the table omits `transform_pi_agent`'s `sed_in_place '/^model: /d'` at line 262, which is equally dead once the source frontmatter loses `model:`.
- Fix: add a row for `scripts/plugin/build.sh:262` to plan.md § Dead Code Removal.

## Design Depth
[no objection: axis checked. Decision [9] names rule-2 criteria 2 and 4 and states the `speq decision-log show` result; its Decision holds no paths or signatures; its `Architecture:` line gives a reason that matches CLAUDE.md's scoping of `specs/architecture.md` to the CLI. The other eight entries are local and `Promotes to ADR: no`, and no entry contradicts an accepted ADR. The installer consumes the generated artifact instead of parsing the table, so the grammar decision has one owner. `scripts/lib/model-routing.sh` hides the grammar behind five helpers, which is deeper than its callers' needs.]

## Prose Quality

#### [PROSE_UNCLEAR] ADVISORY
- Location: plan.md § Context, first bullet
- Issue: "Nine `.claude/agents/*.md` files and six `.claude/skills/*/SKILL.md` files carry `model:` and `effort:` in frontmatter." The six skill files carry only `model:`; no skill file carries `effort:`. The sentence misstates the migration's input.
- Fix: split the sentence: nine agent files carry `model:` and `effort:`, and six skill files carry `model:`.
