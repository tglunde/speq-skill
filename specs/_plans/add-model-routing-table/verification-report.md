# Verification Report: add-model-routing-table

## Verdict

| Result | Details |
|--------|---------|
| **PASS** | One routing table owns every agent and skill routing value. The build validates it, injects harness-specific frontmatter, and emits the Pi overrides artifact; the installer reconciles the operator's Pi settings from that artifact. All 24 implementation tasks, 4 review-fix tasks, and 7 verification tasks complete. |
| Code review | 4 findings — 4 fixed |

| Check | Status |
|-------|--------|
| Build | ✓ |
| Tests | ✓ |
| Lint | ✓ |
| Format | ✓ |
| Scenario Coverage | ✓ |
| Manual Tests | ✓ |

The strongest evidence is the equivalence check: a plugin build from a pristine `HEAD` tree produces a `dist/marketplace` that is **byte-identical** to the new build except for the added `pi/model-overrides.json`. All 136 pre-existing emitted files are unchanged, so the routing table reproduces the old hardcoded behavior exactly.

## Test Evidence

### Coverage

| Type | Coverage % |
|------|------------|
| Unit | n/a |
| Integration | n/a |

Coverage is not measured. This change adds no Rust source: it adds bash tooling (`scripts/lib/model-routing.sh`, `scripts/plugin/render-model-routing-docs.sh`, and edits to `scripts/plugin/build.sh`, `install.sh`, `uninstall.sh`) plus Rust test code only. A `cargo llvm-cov` number would describe the unchanged CLI, not this change. The functional evidence for the new bash is the 25 integration tests below plus the build-gate rejection paths.

### Test Results

| Type | Run | Passed | Ignored |
|------|-----|--------|---------|
| Unit (`src/lib.rs`) | `cargo test` | 206 | 0 |
| Integration (`tests/*.rs`) | `cargo test` | 159 | 0 |
| Doc-tests | `cargo test` | 0 | 0 |
| **Total** | `cargo test` | **365** | **0** |

New tests: 11 in `tests/model_routing.rs`, 14 in `tests/pi_model_overrides.rs`.

### Manual Tests

| Test | Result |
|------|--------|
| `./scripts/plugin/build.sh` — exit 0, guards pass, `dist/marketplace/pi/model-overrides.json` is `{}` | ✓ |
| `./scripts/plugin/render-model-routing-docs.sh` — idempotent | ✓ |
| `diff -r` built `dist/marketplace` against a pre-change build | ✓ |
| `~/.pi/agent/settings.json` hash unchanged across the Pi install path | ✓ |
| `./target/debug/speq plan validate add-model-routing-table` | ✓ |

Evidence for the last three:

```
diff -rq /tmp/speq-baseline/dist/marketplace dist/marketplace
Only in dist/marketplace/pi: model-overrides.json
(136 files before, 137 after — every pre-existing file byte-identical)

shasum -a 256 docs/model-routing.md
9e562939e309b9a6c394e34a84b061b2d03a1b05e29513969a67374ea57e5806   (run 1)
9e562939e309b9a6c394e34a84b061b2d03a1b05e29513969a67374ea57e5806   (run 2)

settings.json before: e99a2260578a7c6f84cabfa4a5b96f5e6fa38e8e1c0b1fccc24d7f537427c0ba
settings.json after:  e99a2260578a7c6f84cabfa4a5b96f5e6fa38e8e1c0b1fccc24d7f537427c0ba
installed agents unchanged: YES
marker after: (0 bytes, written as the empty current pin set)
```

## Tool Evidence

### Linter

```
cargo clippy --all-targets -- -D warnings
    Checking speq-skill v0.25.0 (/Users/torsten/Project/speq-skill/main)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 1.28s
exit=0
```

### Formatter

```
cargo fmt --check
(no output)  exit=0
```

### Build and plugin build

```
cargo build --release   exit=0
./scripts/plugin/build.sh   exit=0
  validator self-test passed (5 malformed rejected, 1 valid accepted)
  coverage 9 agents / 20 skills
  source frontmatter guard passed
  Model routing: scripts/plugin/model-routing.yml
```

## Scenario Coverage

| Domain | Feature | Scenario | Test Location | Test Name | Passes |
|--------|---------|----------|---------------|-----------|--------|
| distribution | model-routing | Build emits Claude routing | `tests/model_routing.rs` | `build_injects_claude_routing` | Pass |
| distribution | model-routing | Build emits Codex routing | `tests/model_routing.rs` | `build_injects_codex_routing` | Pass |
| distribution | model-routing | Build emits Pi reasoning without a model | `tests/model_routing.rs` | `build_emits_pi_thinking_only` | Pass |
| distribution | model-routing | Empty harness map inherits the harness default | `tests/model_routing.rs` | `build_inherits_on_empty_harness_map` | Pass |
| distribution | model-routing | Build rejects syntax outside the subset | `tests/model_routing.rs` | `build_rejects_out_of_subset_line` | Pass |
| distribution | model-routing | Build rejects a source file with no row | `tests/model_routing.rs` | `build_rejects_missing_routing_row` | Pass |
| distribution | model-routing | Build rejects a row with no matching file | `tests/model_routing.rs` | `build_rejects_row_without_file` | Pass |
| distribution | model-routing | Build rejects routing values in source frontmatter | `tests/model_routing.rs` | `build_rejects_source_frontmatter_routing` | Pass |
| distribution | model-routing | Build writes the Pi model overrides artifact | `tests/model_routing.rs` | `build_writes_pi_model_overrides_artifact` | Pass |
| distribution | model-routing | Documentation matches the routing table | `tests/model_routing.rs` | `docs_match_routing_table` | Pass |
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

All 22 scenarios from `plan.md` have a passing test. Three further tests cover behavior the plan's table does not name: `build_does_not_inherit_values_from_a_previous_load` (the regression test for the review's expert finding), `installer_skips_a_malformed_artifact`, and `uninstaller_drops_empty_parent_objects`.

## Notes

### Review findings, all fixed

The review found 4 findings: 3 standard, 1 expert. All were fixed in one pass, each with mutation-proven sensitivity.

- **Expert — `routing_load` inherited values from the previous table.** The parser recorded field values in globals that a later load never cleared, so a load could carry a value from an earlier one. Fixed by recording every field variable in `_ROUTING_FIELD_VARS` and unsetting them at the start of a load. The regression test `build_does_not_inherit_values_from_a_previous_load` was written first and observed failing before the fix.
- **Standard — untested rejection branches.** Added `missing-note-property.yml` and `missing-harness-map.yml` fixtures for the two `finish_row` rejections that had no coverage.
- **Standard — untested skill branch of `guard_source_frontmatter`.** Added `skill-with-routing-frontmatter.md` and extended the test to assert the emitted path and offending value.
- **Standard — a marker assertion that could not detect an absent marker.** `installer_writes_nothing_without_pins` now asserts the marker exists and reads it, so a missing file fails rather than passing vacuously.

### Deliberate deviations from `plan.md` § Manual Testing

1. **The full `./scripts/local-install.sh` was not run.** The plan names it, but that script also uninstalls and reinstalls the Claude plugin, wipes `~/.speq-skill`, overwrites `~/.local/bin/speq`, and prompts interactively about MCP servers — none of which this change touches, and all of which would mutate the operator's live tooling. Instead the verification called `install_pi_agents` directly with the real `HOME` and `MARKETPLACE_DIR=dist/marketplace`, which exercises exactly the code this plan added against the operator's real `settings.json` and real managed agents directory. The evidence for the claim under test (no write when nothing is pinned) is equivalent.
2. **The docs check is render idempotence, not "no diff".** `plan.md` expects `render && git diff --stat docs/model-routing.md` to show no diff, which can only hold once the regenerated document is committed. Since this work is intentionally uncommitted, the check was run as written but interpreted as idempotence: two consecutive renders produce the identical SHA-256.

### Known state and residual risks

- **The uninstaller has no live-run evidence.** Only `tests/pi_model_overrides.rs` covers it, under a temporary `HOME` with a restricted `PATH`. Running it for real would remove the operator's installed Pi agents, so it was not run. The new `.speq-model-overrides` marker (currently 0 bytes) now exists in the operator's `~/.pi/agent/agents/speq/`, so the next real uninstall will read it and remove nothing, which is the designed no-pin behavior.
- **`uninstall.sh` still has no `BASH_SOURCE` guard**, so it cannot be sourced by a test and must run as a subprocess. Left as found; the test pattern handles it.
- **The working tree carries one pre-existing uncommitted change** from recorded plan 001 (`fix-skill-frontmatter-guard`, 127 lines in `scripts/plugin/build.sh`). It is intact and now shares the file with this plan's gates. Both belong to the same uncommitted change set.
- **`.pi/tasks/*.json` is untracked harness runtime state** written by the pi-tasks extension during this session, not part of this change. It is not covered by `.gitignore`, so it appears in `git status`. Consider ignoring `.pi/` or leaving it out of the eventual commit.
- **`docs/model-routing.md` now expands the old aggregated "Utility skills" row into 14 individual rows**, so the rendered tables are longer than the previous hand-written ones. This is intended.
- **Nothing is committed.** 30 paths are dirty: 20 modified tracked files and 9 untracked paths (excluding `dist/`, which is gitignored and regenerated).
