# Verification Report: fix-installer-payload-root

## Verdict

| Result | Details |
|--------|---------|
| **PASS** | Every Pi install reads the agent files and the model-overrides artifact from one current `MARKETPLACE_DIR`. The original failure is fixed end-to-end against two genuinely divergent payload roots. All 384 tests pass, all 16 scenarios have a passing test, and the code review's 5 findings are fixed. |
| Code review | 5 findings — 5 fixed |

| Check | Status |
|-------|--------|
| Build | ✓ |
| Tests | ✓ |
| Lint | ✓ |
| Format | ✓ |
| Scenario Coverage | ✓ |
| Manual Tests | ✓ |

## Test Evidence

### Coverage

| Type | Coverage % |
|------|------------|
| Unit | not measured |
| Integration | not measured |

The plan names no coverage threshold, and the repository has no coverage tooling configured.

### Test Results

| Type | Run | Passed | Ignored |
|------|-----|--------|---------|
| Unit | `mise exec rust@1.96.0 -- cargo test` (`src/lib.rs`) | 206 | 0 |
| Integration | `mise exec rust@1.96.0 -- cargo test` (20 integration targets) | 178 | 0 |
| Integration | `cargo test --test pi_model_overrides` | 22 | 0 |

Total: 384 passed, 0 failed, 0 ignored.

The `pi_model_overrides` target grew from 20 to 22 tests during the fix pass. The two additions are `uninstaller_skips_absent_marketplace_dir` and `uninstaller_removes_default_root_when_marketplace_dir_is_unset_or_empty`.

### Manual Tests

| Test | Result |
|------|--------|
| `cargo test --test pi_model_overrides -- --nocapture` | ✓ 22 passed, 0 failed |
| `bash -n install.sh uninstall.sh scripts/local-install.sh` | ✓ exit 0 |
| `./scripts/plugin/build.sh` | ✓ exit 0, emits `dist/marketplace/pi/model-overrides.json` |
| `./target/debug/speq plan validate fix-installer-payload-root` | ✓ pass |
| Original failure replayed against divergent payload roots | ✓ see below |

The original failure was reproduced by design, not by accident. The two payload roots disagree today: `dist/marketplace/pi/model-overrides.json` carries the `opencode-go/*` pins, and the stale `~/.speq-skill/pi/model-overrides.json` carries the older `opencode/*` pins. The command that wrote the stale pins before this plan was then run again:

```
MARKETPLACE_DIR="$PWD/dist/marketplace" bash -c 'set -euo pipefail; source install.sh; install_pi_agents'
```

`~/.pi/agent/settings.json` was byte-identical before and after, SHA-256 `f1d08b7e4173cee958380622916c62c0e7570956b634084942a990d2476caa3e`, and `speq-planner-agent` and `speq-architecture-agent` both kept `opencode-go/gpt-5.6-luna`. Before this plan the same command read the stale root and reverted those pins. A regression here would flip them back, so this check discriminates the fix from the defect.

## Tool Evidence

### Linter

```
mise exec rust@1.96.0 -- cargo clippy --all-targets
exit 0, 0 warnings, 0 errors
```

### Formatter

```
mise exec rust@1.96.0 -- cargo fmt --check
exit 0, no changes
```

## Scenario Coverage

| Domain | Feature | Scenario | Test Location | Test Name | Passes |
|--------|---------|----------|---------------|-----------|--------|
| distribution | pi-model-overrides | Installer writes the pinned overrides | `tests/pi_model_overrides.rs` | `installer_writes_pinned_overrides` | Pass |
| distribution | pi-model-overrides | Installer creates an absent settings.json | `tests/pi_model_overrides.rs` | `installer_creates_absent_settings` | Pass |
| distribution | pi-model-overrides | Installer writes nothing when no model is pinned | `tests/pi_model_overrides.rs` | `installer_writes_nothing_without_pins` | Pass |
| distribution | pi-model-overrides | Installer removes overrides the previous install recorded but the current payload no longer pins | `tests/pi_model_overrides.rs` | `installer_removes_unpinned_overrides` | Pass |
| distribution | pi-model-overrides | Repeated installs are idempotent | `tests/pi_model_overrides.rs` | `repeated_install_leaves_settings_unchanged` | Pass |
| distribution | pi-model-overrides | Uninstall removes only the entries it wrote | `tests/pi_model_overrides.rs` | `uninstall_removes_only_marked_overrides` | Pass |
| distribution | pi-model-overrides | Uninstaller does nothing when settings.json is absent | `tests/pi_model_overrides.rs` | `uninstaller_noop_without_settings` | Pass |
| distribution | pi-model-overrides | Installer leaves an invalid settings.json untouched | `tests/pi_model_overrides.rs` | `installer_leaves_invalid_settings_untouched` | Pass |
| distribution | pi-model-overrides | Uninstaller leaves an invalid settings.json untouched | `tests/pi_model_overrides.rs` | `uninstaller_leaves_invalid_settings_untouched` | Pass |
| distribution | pi-model-overrides | A failed write leaves the original settings.json byte-identical | `tests/pi_model_overrides.rs` | `failed_write_leaves_settings_byte_identical` | Pass |
| distribution | pi-model-overrides | Installer degrades without a JSON writer | `tests/pi_model_overrides.rs` | `installer_warns_without_json_writer` | Pass |
| distribution | pi-model-overrides | Uninstaller degrades without a JSON writer | `tests/pi_model_overrides.rs` | `uninstaller_warns_without_json_writer` | Pass |
| distribution | pi-model-overrides | Installer uses one payload root for Pi agents and overrides | `tests/pi_model_overrides.rs` | `installer_uses_one_payload_root_for_agents_and_overrides` | Pass |
| distribution | pi-model-overrides | Uninstaller honors a caller-provided marketplace directory | `tests/pi_model_overrides.rs` | `uninstaller_honors_marketplace_dir_override` | Pass |
| distribution | pi-model-overrides | Uninstaller skips an absent marketplace directory | `tests/pi_model_overrides.rs` | `uninstaller_skips_absent_marketplace_dir` | Pass |
| distribution | pi-model-overrides | Uninstaller guards marketplace removal targets and preserves valid cleanup | `tests/pi_model_overrides.rs` | `uninstaller_guards_marketplace_removal_targets` | Pass |

All 16 scenarios pass. Six further tests in the same target cover behavior no scenario names: `installer_skips_a_malformed_artifact`, `installer_skips_pins_for_an_unconfigured_provider`, `installer_writes_a_bare_model_id_without_a_provider_check`, `installer_removes_a_stale_override_for_a_now_unconfigured_provider`, `uninstaller_drops_empty_parent_objects`, and `uninstaller_removes_default_root_when_marketplace_dir_is_unset_or_empty`.

## Notes

### Red-to-green evidence

Each behavior change was observed failing first.

- `installer_uses_one_payload_root_for_agents_and_overrides` failed against the old wiring for both blocks. Block (a) failed because the old unconditional assignment overwrote the exported caller root. Block (b) failed because the default root's pin was written.
- `uninstaller_skips_absent_marketplace_dir` failed against the pre-1.6 guard with exit 1 and the message "no install marker". It passes after the guard distinguishes an absent path from an existing unmarked one.
- `uninstaller_removes_default_root_when_marketplace_dir_is_unset_or_empty` was proven against a simulated `${MARKETPLACE_DIR-...}` regression. The colon is what makes the default apply to an empty value, and the suite now fails without it.

### Behavior the guard enforces

`guard_marketplace_removal_target` runs as the first statement of `main`. It rejects `/`, exactly `$HOME`, and an existing path without `.claude-plugin/marketplace.json`, exits 1, and names the rejected directory. An absent path passes the guard, and the removal step's own `[ -d ]` and `else` pair warns and skips only that step. The skip condition therefore has one owner, the removal predicate, instead of a second code path that can drift from it. The `-e` check means an existing non-directory keeps the hard failure.

### The `/` case cannot reach the real `rm`

The code review's expert finding was that the guard test ran `uninstall.sh` with `MARKETPLACE_DIR` set to `/`, and the guard was the only barrier before step 8 executed `rm -rf /`. macOS `rm` has no root failsafe, so a regressed guard would have deleted operator data before any assertion could fail. The fix pass added an `rm` wrapper to the fake bin that executes `/bin/rm` only when every non-flag argument matches `"$HOME"/*`, and otherwise refuses with a path-free message. Both end-to-end uninstaller tests install the wrapper.

### Deliberate deviations

1. **The full `./scripts/local-install.sh` was not run.** The plan excludes an end-to-end test of it, and the script also uninstalls and reinstalls the Claude plugin, wipes `~/.speq-skill`, overwrites `~/.local/bin/speq`, and prompts about MCP servers. The caller-root command above exercises the same sourced installer against the operator's real `settings.json` and real divergent roots.
2. **Cargo ran through an explicit tool version.** This shell has no default rust version, so every cargo command used `mise exec rust@1.96.0 --`. No `mise.toml` was written.

### Known state

- **The absent-marketplace change was user-directed after code review.** The plan review and the clarifying interview both missed that the guard treated an absent `MARKETPLACE_DIR` as unsafe, which aborted steps 1 to 7 and left the CLI binary, Pi agents, Codex skills, and Claude plugin installed. The user directed the absent-versus-unsafe distinction. Decision-log entry [6] records it, and a `[plan-review]` entry records the gap.
- **The code review's 5 findings did not include the absent-marketplace gap.** Its findings covered the test harness and one stale comment. The gap was found by the orchestrator while inspecting the guard.
- **`install.sh` and `uninstall.sh` mix a pre-existing version bump with this plan's hunks.** Both files were already uncommitted before this plan. The code reviewer was told to attribute the version-bump lines correctly and excluded them.
- **Nothing is committed.** The working tree carries the version bump, the recorded `add-model-routing-table` change set, and this plan. `specs/_recorded/` is gitignored through `specs/.gitignore: /_recorded`, so the archived plan from the earlier record step does not appear in `git status`.
- **`.pi/tasks/*.json` is untracked harness runtime state** written by the pi-tasks extension. It is not covered by `.gitignore`.
