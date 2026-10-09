# Code Review Findings: add-model-routing-table

## Summary
- Files reviewed: 45 (5 new scripts and test files, 20 new fixtures, 20 modified files)
- Total findings: 4 (standard: 3, expert: 1)

Verified during the review: all 24 new tests pass, `cargo fmt --check` and `cargo clippy --tests` are clean, the test suite leaves the repository `dist/` byte-identical, the installer tests reach only the temporary `HOME`, and a build from the pre-change tree produces a payload identical to the current build except the added `pi/model-overrides.json`.

## Standard fixes

### tests/model_routing.rs

#### [UNTESTED_ERROR_PATH] The missing `note:` and missing harness-map branches have no fixture
- Location: line 268 (`build_rejects_out_of_subset_line`)
- Issue: `finish_row` in `scripts/lib/model-routing.sh` rejects a row without `note:`, `claude:`, `codex:`, or `pi:`, and the plan's requirement states "A missing `file:`, `note:`, or harness map is an error". Only the missing `file:` branch has a fixture (`missing-file-property.yml`, and `row-without-file.yml` in the build self-test). A probe confirms the other four branches print their message and exit 1, and no test asserts any of them, so a regression that turned one into a warning would leave the suite green.
- Fix: Add two fixtures under `tests/fixtures/model_routing/tables/`, modelled on `missing-file-property.yml`. Name the first `missing-note-property.yml`: an `agents:` header, a `planner-agent` row carrying `file: .claude/agents/planner-agent.md`, `claude: {}`, `codex: {}`, `pi: {}` and no `note:`, then an empty `skills:` header. Name the second `missing-harness-map.yml`: the same row carrying `file:`, `note: Fixture row without a pi: map`, `claude: {}`, `codex: {}` and no `pi:`, then an empty `skills:` header. Add `("missing-note-property.yml", "has no note: property")` and `("missing-harness-map.yml", "has no pi: map")` to the `cases` array in `build_rejects_out_of_subset_line`.

#### [UNTESTED_ERROR_PATH] The source guard's skill branch has no test
- Location: line 331 (`build_rejects_source_frontmatter_routing`)
- Issue: `guard_source_frontmatter` (scripts/plugin/build.sh:617) scans `$SOURCE_DIR/agents/*.md` and `$SOURCE_DIR/skills/speq-*/SKILL.md` in one loop, and the spec scenario covers "a source agent or skill". The test replaces only an agent file, so nothing fails when the skills glob stops matching: a typo there silently disables half of a hard build gate. A probe confirms the skill branch works today, so the gap is test coverage alone.
- Fix: Add `tests/fixtures/model_routing/sources/skill-with-routing-frontmatter.md` with a `---` frontmatter block carrying `name: speq-plan`, a `description:` line, `model: sonnet`, and a closing `---`. In `build_rejects_source_frontmatter_routing` in tests/model_routing.rs, copy that fixture over `.claude/skills/speq-plan/SKILL.md` in the same temporary project, and add assertions that the build output contains `.claude/skills/speq-plan/SKILL.md:` and `model: sonnet`.

### tests/pi_model_overrides.rs

#### [SWALLOWED_ERROR] The marker assertion cannot detect an absent marker
- Location: line 232 (`installer_writes_nothing_without_pins`)
- Issue: `fs::read_to_string(marker_path(home.path())).unwrap_or_default()` turns a missing marker file into `""`, so the assertion passes whether the installer wrote an empty marker or no marker at all. Task 2.1 requires the installer to rewrite the marker to the empty current set, and the plan review's second blocker was a lost marker. A manual run of `install_pi_agents` against `artifact_empty.json` writes a zero-byte marker, so the assertion passes for the right reason today but cannot catch a regression to "leave the marker absent".
- Fix: In `installer_writes_nothing_without_pins` in tests/pi_model_overrides.rs, add `assert!(marker_path(home.path()).exists(), "the installer must rewrite the marker to the empty set");` before the content assertion, and replace `fs::read_to_string(marker_path(home.path())).unwrap_or_default()` with `read(&marker_path(home.path()))` so a missing file fails with the path in the message.

## Expert fixes

### scripts/lib/model-routing.sh

#### [SIDE_EFFECT] `routing_load` keeps harness values from the previously loaded table
- Location: line 21 (`routing_load`), header comment line 15
- Issue: `routing_load` overwrites only the fields the new table sets, so a value an earlier load set survives into the new table. Verified: loading a table whose `planner-agent` row has `claude: { model: opus, effort: xhigh }` and then one whose row has `claude: {}` leaves `routing_value agents planner-agent claude model` at `opus`. `build.sh` calls `routing_load` seven times per process (five malformed self-test fixtures, one valid self-test fixture, then the real table), so the self-test fixture's values mask a value removed from the real table. Verified end to end: with `claude: {}` in the real table, the emitted Claude copy still carries `model: opus` and `effort: xhigh`, and `build_injects_claude_routing` (tests/model_routing.rs:206) asserts exactly those lines, so the suite confirms a payload that contradicts the table. The header comment's claim that "routing_load is meant to be called once per process" is the contract `build.sh` violates.
- Fix: In scripts/lib/model-routing.sh, track every field variable name `routing_load` sets in a `_ROUTING_FIELD_VARS` string list (append the variable name next to each of the three `printf -v` calls) and `unset` each recorded name at the start of `routing_load`, before the `awk` run, so a load replaces the previous table instead of merging into it. Replace the header comment sentence "routing_load is meant to be called once per process." with a statement that a load replaces the previous table and clears every field it set. Add a regression test named `build_does_not_inherit_values_from_a_previous_load` to tests/model_routing.rs: call `setup_project`, replace the first occurrence of `claude: { model: opus, effort: xhigh }` in the copied `scripts/plugin/model-routing.yml` with `claude: {}` (assert the text changed, mirroring the `replacen` mutation in `build_writes_pi_model_overrides_artifact`), run the build, and assert the emitted Claude copy of `planner-agent` carries no `model:` or `effort:` line.
