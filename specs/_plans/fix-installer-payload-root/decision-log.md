# Decision Log: fix-installer-payload-root

## Interview

**Q1:** How deep should the fix go into the payload-root wiring?
**A:** Use one payload root. Bind the artifact path inside `install_pi_agents` from the same `MARKETPLACE_DIR` it uses for agent files. Make `install.sh` and `uninstall.sh` honor a caller-provided `MARKETPLACE_DIR` with `${MARKETPLACE_DIR:-$HOME/.speq-skill}`. Set the local-install value before sourcing `install.sh`.

**Q2:** `add-model-routing-table` is implemented and verified but not yet recorded. What should this fix build on?
**A:** Record it first. `distribution/model-routing` and `distribution/pi-model-overrides` are permanent, the plan is archived at `specs/_recorded/002-add-model-routing-table`, and ADR `one-routing-table-owns-model-and-effort` is accepted. Its verification report records that the claimed `./scripts/local-install.sh` coverage did not run.

**Q3:** Which regression test should prove the fix?
**A:** Add the split-root case in `tests/pi_model_overrides.rs`. Give the agent payload and pin artifact different roots and assert that the installing payload's pins win. Extend the existing harness and do not add an end-to-end `local-install.sh` test.

## Design Decisions

### [1] Resolve the Pi artifact from the current payload root

- **Decision:** `install_pi_agents` derives the model-overrides artifact path from the current `MARKETPLACE_DIR` at function execution time, next to the agent source path.
- **Alternatives:** Keep a source-time global artifact path; it can retain a different root after `MARKETPLACE_DIR` changes. Copy the artifact into the default marketplace first; it masks the split-root defect and couples correctness to operation order.
- **Rationale:** The installer has one payload-root owner. Keeping both paths beside the function that consumes them prevents a source-time value from becoming stale and follows the design principle that one module owns each format and data-flow decision.
- **Consequences:** Callers that source `install.sh` and set `MARKETPLACE_DIR` later still use one root for the Pi agent files and the artifact. The generated artifact contract and routing values do not change.
- **Promotes to ADR:** no

### [2] Make marketplace-root defaults environment-aware before deriving dependent paths

- **Decision:** `install.sh` and `uninstall.sh` initialize `MARKETPLACE_DIR` with `${MARKETPLACE_DIR:-$HOME/.speq-skill}`. `scripts/local-install.sh` assigns its local-build default before sourcing `install.sh` and does not overwrite a caller-provided value afterward.
- **Alternatives:** Assign the local root after sourcing; this leaves source-time derived values stale. Require callers to edit the scripts; this prevents local and temporary installs from selecting a complete payload root.
- **Rationale:** The caller-provided value must govern every operation that reads or removes the marketplace. Dependent paths must be derived after the default is resolved so the default remains unchanged while overrides work.
- **Consequences:** Existing invocations without `MARKETPLACE_DIR` keep using `$HOME/.speq-skill`. Local builds use `dist/marketplace` by default, while callers can select another root. `CODEX_MARKETPLACE_ROOT` and any other source-time derived value assume `MARKETPLACE_DIR` is final before `install.sh` is sourced; assignment after sourcing is not supported.
- **Promotes to ADR:** no

### [3] Prove the failure with a split-root harness case

- **Decision:** Extend `tests/pi_model_overrides.rs` to construct distinct old and installing payload roots, invoke `install_pi_agents` after the runtime root changes, and assert both the copied agent and settings pin come from the installing root. Add a focused uninstaller subprocess assertion for the caller-provided marketplace directory.
- **Alternatives:** Add an end-to-end `scripts/local-install.sh` test; it mutates live installation locations and does not isolate the function-level root mismatch. Test only the settings artifact; it would not prove that the agent files and artifact share a root.
- **Rationale:** The existing harness already isolates `HOME`, controls `PATH`, and invokes the relevant installer and uninstaller paths. The split-root setup targets the observed source-time/runtime-time mismatch without exercising unrelated local-install prompts or plugin registration.
- **Consequences:** The regression test covers the defect directly. The local-install script remains covered by static shell validation and the same sourced installer behavior, not by a destructive end-to-end test.
- **Promotes to ADR:** no

### [4] Preserve the recorded routing-table contract

- **Decision:** Treat `pi/model-overrides.json` as the existing generated payload artifact and change only how the installer selects its root.
- **Alternatives:** Move routing-table parsing into the installer; this duplicates the build contract and contradicts accepted ADR `one-routing-table-owns-model-and-effort`.
- **Rationale:** The accepted ADR `005-add-model-routing-table` already makes one routing table own model and effort values, and the permanent distribution specs define the artifact consumed by the installer. This plan conforms to that decision and does not change model-routing semantics.
- **Architecture:** no change: `specs/architecture.md` describes the Rust CLI, while this plan changes repository installer scripts and their integration harness.
- **Promotes to ADR:** no

### [5] Guard destructive marketplace cleanup targets

- **Decision:** Before any removal, `uninstall.sh` rejects `/`, exactly `$HOME`, and any `MARKETPLACE_DIR` without `.claude-plugin/marketplace.json`. The guard exits non-zero and names the rejected directory.
- **Alternatives:** Allow every caller-provided target; a broad or mistyped target could remove operator data. Reject only `/` and `$HOME`; this does not establish that an arbitrary target is an installed marketplace.
- **Rationale:** Every installed marketplace root carries `.claude-plugin/marketplace.json`, so requiring that marker is the narrowest repository-backed proof that the target is an installation. Explicitly rejecting `/` and `$HOME` adds protection for the two broad roots even if a marker is present there. This local uninstaller constraint is a one-off safety fix and does not meet `/speq:adr-rules` rule 2 criteria.
- **Consequences:** A valid marked installation still uninstalls normally. An unsafe or unmarked target stops the uninstaller before any removal and reports the target path.
- **Promotes to ADR:** no

### [6] Distinguish absent and unsafe marketplace targets

- **Decision:** `uninstall.sh` treats an absent `MARKETPLACE_DIR` as already removed: it warns, skips only marketplace removal, continues the remaining uninstall steps, and exits successfully. It treats an existing directory without `.claude-plugin/marketplace.json` as unsafe and keeps the hard failure. The `/` and exactly `$HOME` rejections remain unchanged.
- **Alternatives:** Reject every absent or unmarked path; this breaks idempotent uninstall when the marketplace directory was already removed. Treat every absent or unmarked path as already removed; this permits removal from an unsafe existing directory.
- **Rationale:** Absence means there is no marketplace directory for step 8 to remove, so the uninstaller can preserve idempotency while still cleaning the remaining installation. An existing directory without the install marker does not prove that it is a marketplace, so the guard must stop before any removal. This one-off safety distinction does not meet `/speq-adr-rules` rule 2 criteria.
- **Consequences:** Re-running the uninstaller after marketplace removal succeeds and cleans any remaining components. An existing unmarked target remains protected by the non-zero guard failure.
- **Promotes to ADR:** no

## Review Findings

### [plan-review] Guard the destructive marketplace removal

- **Finding:** Round 1 Advisory `[NFR_IGNORED]` identified that a caller-provided uninstaller root could make `rm -rf` remove `/`, `$HOME`, or another operator directory.
- **Direction change:** Added a pre-removal guard requiring the installed marketplace marker, explicitly rejecting `/` and `$HOME`, and added the requirement, scenario, task, and two-outcome integration test coverage.
- **Promotes to ADR:** no

### [plan-review] State the source-time root invariant

- **Finding:** Round 1 Advisory `[UNSTATED_ASSUMPTION]` identified that source-time values such as `CODEX_MARKETPLACE_ROOT` become stale when `MARKETPLACE_DIR` changes after `install.sh` is sourced.
- **Direction change:** Added the requested sentence to the Consequences line of design decision [2].
- **Promotes to ADR:** no

### [plan-review] Split the payload-root test invocations

- **Finding:** Round 1 Advisory `[PROSE_UNCLEAR]` identified that task 1.4 combined two bash invocation shapes and could omit coverage of the caller override.
- **Direction change:** Rewrote task 1.4 as clauses (a) and (b), with one independent invocation for the pre-source caller override and one for the post-source installing-root switch.
- **Promotes to ADR:** no

### [plan-review] Distinguish absent and unsafe marketplace targets

- **Finding:** The plan review and the interview both missed the absent `MARKETPLACE_DIR` case. The existing guard treats an absent directory as unmarked and aborts before the remaining uninstall steps, which breaks idempotent uninstall.
- **Direction change:** The user directed the fix. Added a separate absent-target scenario, limited the marker requirement to existing directories, documented the warning and continued cleanup behavior, added scenario coverage, and added task 1.6. Existing unmarked directories, `/`, and exactly `$HOME` remain hard failures.
- **Promotes to ADR:** no
