# Plan: fix-installer-payload-root

## Summary

Make every Pi install read agent files and model overrides from one current `MARKETPLACE_DIR`. Preserve the existing default, honor caller-provided roots in both installer scripts, initialize the local-install root before sourcing, and prove the fix with a split-root regression test.

## Context

- `install.sh` currently assigns `MARKETPLACE_DIR` unconditionally and computes `PI_OVERRIDES_ARTIFACT` when the file is sourced.
- `install_pi_agents` later reads agent files from the current `MARKETPLACE_DIR`, so a caller or local script can make the agent files and artifact come from different roots.
- `scripts/local-install.sh` assigns its `dist/marketplace` root after sourcing `install.sh`, which preserves the stale artifact path.
- `uninstall.sh` has the same unconditional marketplace-root assignment, so callers cannot direct its marketplace cleanup to a temporary or local root.
- Once the uninstaller honors a caller-provided root, its destructive marketplace cleanup needs a marker guard so a broad or mistyped target cannot remove operator data.
- The existing Pi override harness creates only `$HOME/.speq-skill`, so it cannot represent the two roots that trigger the defect.
- The routing-table and Pi override features from the recorded `add-model-routing-table` plan are permanent, and ADR `one-routing-table-owns-model-and-effort` owns the routing semantics. This plan changes only payload-root selection.
- `specs/architecture.md` covers the Rust CLI and has no installer component or data flow. No architecture delta is required.

## Features

| Feature | Status | Spec |
|---------|--------|------|
| distribution/pi-model-overrides | CHANGED | `distribution/pi-model-overrides/spec.md` |

## Impact

Callers can set `MARKETPLACE_DIR` to install or uninstall a complete alternate marketplace tree. Invocations without the variable keep using `$HOME/.speq-skill`. Local builds use `dist/marketplace` as their default root before the installer is sourced, so the Pi agents and generated pins stay aligned.

## Requirements

| Requirement | Details |
|-------------|---------|
| One payload root | `install_pi_agents` MUST resolve both `pi/agents` and `pi/model-overrides.json` under the same current `MARKETPLACE_DIR`. |
| Caller override | `install.sh` and `uninstall.sh` MUST preserve a caller-provided `MARKETPLACE_DIR` and MUST default it to `$HOME/.speq-skill` only when it is unset or empty. |
| Local-build ordering | `scripts/local-install.sh` MUST set its `dist/marketplace` default before sourcing `install.sh` and MUST NOT overwrite a caller-provided root afterward. |
| Uninstall safety guard | Before removing an existing marketplace directory, `uninstall.sh` MUST reject `MARKETPLACE_DIR` when it is `/`, exactly `$HOME`, or is an existing directory that lacks the install marker `.claude-plugin/marketplace.json`; it MUST exit non-zero and name the rejected directory. When `MARKETPLACE_DIR` does not exist, `uninstall.sh` MUST warn and name the directory, skip only marketplace removal, continue the remaining uninstall steps, and exit 0. A valid installed marketplace root containing the marker MUST still uninstall normally. |
| Existing reconciliation | The installer and uninstaller MUST retain the existing settings merge, marker, invalid-document, and degraded-writer behavior. |
| Regression proof | The integration harness MUST exercise distinct payload roots and assert that the installing root's agent and pin artifact win. No end-to-end `local-install.sh` test is added. |

## Dependencies

- The generated `pi/model-overrides.json` artifact and its semantics from `distribution/model-routing` and `distribution/pi-model-overrides`.
- Accepted ADR `one-routing-table-owns-model-and-effort` from the recorded routing-table plan.

## Migration

No data migration is required. Existing installations keep their managed agent directory and settings marker. A caller that previously set `MARKETPLACE_DIR` and had it ignored will now target that directory as requested.

## Implementation Tasks

1.1 [expert] Update `install.sh` so `${MARKETPLACE_DIR:-$HOME/.speq-skill}` is resolved before dependent paths, remove the source-time `PI_OVERRIDES_ARTIFACT` value, and bind `MARKETPLACE_DIR/pi/model-overrides.json` inside `install_pi_agents` beside its agent source path. Preserve all current reconciliation and malformed-artifact behavior.

1.2 Update `uninstall.sh` to resolve `${MARKETPLACE_DIR:-$HOME/.speq-skill}` without overwriting a caller value. Before any removal, reject `/`, exactly `$HOME`, and any root without `.claude-plugin/marketplace.json`, exit non-zero, and name the rejected directory. Ensure a valid marked root remains the one used for marketplace removal and Codex symlink ownership checks.

1.3 Update `scripts/local-install.sh` to assign `MARKETPLACE_DIR="${MARKETPLACE_DIR:-${PROJECT_ROOT}/dist/marketplace}"` before `source "$PROJECT_ROOT/install.sh"`, and remove the later unconditional assignment. Keep the local build root as the default while allowing a caller override.

1.4 [expert] Extend `tests/pi_model_overrides.rs`'s payload helpers to create arbitrary roots with distinguishable agent content and bare model-id artifacts. Add a split-root regression test with two independent bash invocations:
   (a) export `MARKETPLACE_DIR=<caller-root>`, source `install.sh` with a populated `$HOME/.speq-skill` default root, call `install_pi_agents`, and assert the caller root's agent file and pin win;
   (b) source `install.sh` with `MARKETPLACE_DIR` unset and a populated default root, assign `MARKETPLACE_DIR=<installing-root>`, call `install_pi_agents`, and assert the installing root's agent file and pin win and the default root's pin is ignored.

1.5 Extend the existing restricted-`HOME` uninstaller harness with a caller-root guard test named `uninstaller_guards_marketplace_removal_targets`. Exercise `/`, exactly `$HOME`, and an unmarked temporary target as unsafe roots. For each unsafe root, run `uninstall.sh` with `MARKETPLACE_DIR` set to that root and assert that it exits non-zero, names the rejected directory, and leaves the target intact. Then give a separate temporary marketplace a `.claude-plugin/marketplace.json` marker, run a valid uninstall, and assert that this directory is removed while a second marketplace directory is retained. Seed the existing valid uninstaller cases with the marker fixture so normal uninstalls remain successful. Keep the fake Claude and Codex executables and restricted `PATH` isolation.

1.6 Refine the uninstaller marketplace-target guard so a missing `MARKETPLACE_DIR` emits a warning naming the directory, skips only marketplace removal, continues the remaining uninstall steps, and exits 0. Keep `/`, exactly `$HOME`, and an existing directory without `.claude-plugin/marketplace.json` as hard failures that name the rejected directory and remove nothing.

2.1 Verification pass: run plan validation, the Pi override integration test, shell syntax checks, the plugin build, the Rust build, the full Rust test suite, formatting, and linting. Confirm the split-root test fails against the old source-time artifact wiring before accepting the implementation.

## Parallelization

| Group | Tasks | Depends on | Knowledge |
|-------|-------|------------|-----------|
| A: payload-root wiring and regression proof | 1.1-1.6, 2.1 | — | spec delta `distribution/pi-model-overrides`; `install.sh` (`install_pi_agents` and root defaults), `uninstall.sh` (`remove_pi_agents` and marketplace cleanup), `scripts/local-install.sh`, `tests/pi_model_overrides.rs` helpers and subprocess harness |

The group is one vertical slice because the defect crosses source-time shell variables, function-time payload reads, local-install ordering, and one shared integration harness. Task 1.1 is tagged `[expert]`, so the group requires expert implementation routing.

## Dead Code Removal

| Type | Location | Reason |
|------|----------|--------|
| Variable | `install.sh` `PI_OVERRIDES_ARTIFACT` | Replaced by the function-local artifact path derived from the current `MARKETPLACE_DIR`. |
| Assignment | `scripts/local-install.sh` late `MARKETPLACE_DIR` assignment | Replaced by the pre-source default that does not overwrite a caller-provided value. |

## Verification

### Scenario Coverage

| Scenario | Test Type | Test Location | Test Name |
|----------|-----------|---------------|-----------|
| Installer writes the pinned overrides | Integration | `tests/pi_model_overrides.rs` | `installer_writes_pinned_overrides` |
| Installer creates an absent settings.json | Integration | `tests/pi_model_overrides.rs` | `installer_creates_absent_settings` |
| Installer writes nothing when no model is pinned | Integration | `tests/pi_model_overrides.rs` | `installer_writes_nothing_without_pins` |
| Installer removes overrides the previous install recorded but the current payload no longer pins | Integration | `tests/pi_model_overrides.rs` | `installer_removes_unpinned_overrides` |
| Repeated installs are idempotent | Integration | `tests/pi_model_overrides.rs` | `repeated_install_leaves_settings_unchanged` |
| Uninstall removes only the entries it wrote | Integration | `tests/pi_model_overrides.rs` | `uninstall_removes_only_marked_overrides` |
| Uninstaller does nothing when settings.json is absent | Integration | `tests/pi_model_overrides.rs` | `uninstaller_noop_without_settings` |
| Installer leaves an invalid settings.json untouched | Integration | `tests/pi_model_overrides.rs` | `installer_leaves_invalid_settings_untouched` |
| Uninstaller leaves an invalid settings.json untouched | Integration | `tests/pi_model_overrides.rs` | `uninstaller_leaves_invalid_settings_untouched` |
| A failed write leaves the original settings.json byte-identical | Integration | `tests/pi_model_overrides.rs` | `failed_write_leaves_settings_byte_identical` |
| Installer degrades without a JSON writer | Integration | `tests/pi_model_overrides.rs` | `installer_warns_without_json_writer` |
| Uninstaller degrades without a JSON writer | Integration | `tests/pi_model_overrides.rs` | `uninstaller_warns_without_json_writer` |
| Installer uses one payload root for Pi agents and overrides | Integration | `tests/pi_model_overrides.rs` | `installer_uses_one_payload_root_for_agents_and_overrides` |
| Uninstaller honors a caller-provided marketplace directory | Integration | `tests/pi_model_overrides.rs` | `uninstaller_honors_marketplace_dir_override` |
| Uninstaller skips an absent marketplace directory | Integration | `tests/pi_model_overrides.rs` | `uninstaller_skips_absent_marketplace_dir` |
| Uninstaller guards marketplace removal targets and preserves valid cleanup | Integration | `tests/pi_model_overrides.rs` | `uninstaller_guards_marketplace_removal_targets` |

### Manual Testing

| Feature | Command | Expected Output |
|---------|---------|-----------------|
| distribution/pi-model-overrides | `cargo test --test pi_model_overrides -- --nocapture` | All installer and uninstaller integration tests pass, including the split-root and caller-root cases. |
| distribution/pi-model-overrides | `bash -n install.sh uninstall.sh scripts/local-install.sh` | Exit 0 with no shell syntax errors. |
| distribution/pi-model-overrides | `./scripts/plugin/build.sh` | Exit 0 and emit the existing `pi/model-overrides.json` artifact. |
| distribution/pi-model-overrides | `./target/debug/speq plan validate fix-installer-payload-root` | Plan validation passes for the delta and all plan artifacts. |

### Checklist

| Step | Command | Expected |
|------|---------|----------|
| Build | `cargo build --release` | Exit 0 |
| Test | `cargo test` | 0 failures |
| Lint | `cargo fmt && cargo clippy` | 0 errors or warnings |
| Format | `cargo fmt --check` | No changes |
| Plugin build | `./scripts/plugin/build.sh` | Exit 0 |
| Plan validation | `./target/debug/speq plan validate fix-installer-payload-root` | Pass |
