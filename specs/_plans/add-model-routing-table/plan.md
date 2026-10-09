# Plan: add-model-routing-table

## Summary

Replace the model and effort values that `scripts/plugin/build.sh` hardcodes and the source frontmatter duplicates with one restricted-syntax YAML routing table. The build validates the table, injects the harness-specific frontmatter, and emits the Pi model overrides artifact; the installer propagates those overrides into the operator's Pi settings.

## Context

- Nine `.claude/agents/*.md` files carry `model:` and `effort:` in frontmatter. Six `.claude/skills/*/SKILL.md` files carry `model:`. `build.sh` rewrites them for Codex from two hardcoded name lists (`set_codex_agent_model`, `set_codex_skill_model`) and strips them for Pi.
- `docs/model-routing.md` repeats every value in three hand-written tables, so each routing edit touches three places and drifts when one is missed.
- `install.sh` never reads or writes `~/.pi/agent/settings.json`. Pi resolves `subagents.agentOverrides.<name>.model` from that file before the agent's frontmatter.
- The scripts tree has no YAML parser. Recorded plan 001 (`fix-skill-frontmatter-guard`) set the precedent: build-time guards in pure bash and awk, no new dependency.
- `specs/mission.md` capability 14 names the plugin build and the installer; no feature spec covers either.
- No architecture delta: `specs/architecture.md` covers the CLI only, and this plan changes build and install tooling.

## Features

| Feature | Status | Spec |
|---------|--------|------|
| distribution/model-routing | NEW | `distribution/model-routing/spec.md` |
| distribution/pi-model-overrides | NEW | `distribution/pi-model-overrides/spec.md` |

## Impact

- No visible change for end users with the shipped table: it pins no Pi model, so the installer writes no override and the uninstaller removes none. No CHANGELOG entry follows, because nothing user-visible changes until a row pins a Pi model.
- Contributors edit routing in one file. The in-repo `.claude/agents/*.md` lose `model:` and `effort:`, and the six skill files lose `model:`, so agents and skills invoked from the repository tree run on the session model; the built plugin trees keep the pinned routing.
- Breaking change for a contributor who adds routing to frontmatter: the build fails on a source `model:`, `effort:`, or `thinking:` line until the value moves to the table.
- `docs/model-routing.md` keeps its prose and gains generated routing tables.

## Requirements

| Requirement | Details |
|-------------|---------|
| No new dependency | `build.sh`, `install.sh`, and `uninstall.sh` stay bash + coreutils + awk/sed/perl. The installer's and the uninstaller's JSON merges use perl's core `JSON::PP` module. A missing module never causes a partial write: the installer warns and prints the JSON to add, and the uninstaller warns, lists the `subagents.agentOverrides` entries to remove manually, and exits 0 without touching the file. |
| Restricted subset | The routing table's grammar is fixed and validated. A line outside the subset fails the build with file, line, and offending content. An empty harness map injects nothing and renders as `inherited`. |
| Hard failures | A source agent or skill with no row, a row whose file is absent or misnamed, and a source `model:`/`effort:`/`thinking:` line each fail the build before it writes an artifact. |
| Never ship the table | No plugin payload directory contains `model-routing.yml`. |
| Operator-owned settings | The installer preserves every unrelated key in `settings.json`, writes only when the serialized result differs, and removes on uninstall only the entries it recorded as its own. It creates the file only when it pins at least one model, leaves an invalid document untouched with a warning, and writes through a temporary file plus a rename, so a failed write leaves the original byte-identical. |

### Routing table subset

The table is a line-oriented YAML subset. This shape is the whole grammar:

```yaml
# Full-line comment or blank line.
agents:
  planner-agent:
    file: .claude/agents/planner-agent.md
    note: Spec deltas, context, task decomposition
    claude: { model: opus, effort: xhigh }
    codex: { model: gpt-5.5, effort: xhigh }
    pi: { model: null, thinking: xhigh }
```

- Indentation is spaces only, at 0, 2, or 4 columns. A tab anywhere is an error.
- Blank lines and lines whose first non-space character is `#` are ignored. An inline comment is not part of the subset.
- Section headers: `agents:` and `skills:`, each exactly once, in any order. Any other column-0 line is an error.
- Rows: `  <name>:` where `<name>` matches `[a-z0-9][a-z0-9-]*`; each name appears once per section.
- Properties: `file:`, `note:`, `claude:`, `codex:`, `pi:`, each exactly once per row.
  - `file:` is a repository-relative path. An agent row MUST name `.claude/agents/<name>.md`; a skill row MUST name `.claude/skills/<name>/SKILL.md`.
  - `note:` is non-empty free text without `|`, so it renders inside a Markdown table cell.
  - The harness values are inline flow maps: `{ key: value, ... }`, possibly empty (`{}`). An empty map injects nothing and means the harness inherits its default. Whitespace inside the braces is arbitrary.
- Flow-map keys: `model` and `effort` under `claude` and `codex`; `model` and `thinking` under `pi`. Each key appears at most once per map.
- Flow-map values: `null`, or a plain scalar matching `[A-Za-z0-9._/-]+`. Quoted scalars, block scalars, anchors, aliases, nested maps, multi-line values, and unknown keys are errors.
- A missing `file:`, `note:`, or harness map is an error.
- Every error prints `<file>:<line>: <message>` followed by the offending line, and the build exits non-zero before it writes any artifact.

Coverage checks, after the syntax passes:

- The `file:` values of the `agents` section equal the set of `.claude/agents/*.md` files.
- The `file:` values of the `skills` section equal the set of `.claude/skills/speq-*/SKILL.md` files.
- A missing row names the source file. A row without a matching file names the row and the expected path.

## Migration

| Current | New |
|---------|-----|
| `model:` and `effort:` in `.claude/agents/*.md` (9 files) | `claude:`, `codex:`, `pi:` maps in `model-routing.yml` |
| `model:` in `.claude/skills/*/SKILL.md` (6 files) | `claude:` and `codex:` maps in the table |
| `set_codex_agent_model` and `set_codex_skill_model` name lists in `build.sh` | `codex:` maps in the table |
| Hand-written tables in `docs/model-routing.md` | Generated blocks from the table |

## Implementation Tasks

1.1 Add `scripts/lib/model-routing.sh`: the restricted-subset parser, the coverage check, and the lookup helpers (`routing_load <file>`, `routing_value <section> <name> <harness> <key>`, `routing_names <section>`, `routing_note <section> <name>`, `routing_check_coverage <source-dir>`). Bash 3.2 compatible: no associative arrays, no `mapfile`. Every error prints `file:line: message` plus the offending line. [expert]
1.2 Write `model-routing.yml` at the repository root with a row for each of the 9 agents and 20 skills. Values come from the current source frontmatter and the two `build.sh` lists. Every agent `pi:` map is `{ model: null, thinking: <source effort> }`, and every skill `pi:` map is `{}`. The six skills that carry `model:` today get `claude:` and `codex:` maps from that value; the other 14 utility skills get `claude: {}` and `codex: {}` with the shared note from the current "Utility skills" row. Notes come from the current `docs/model-routing.md` tables. Add one `CLAUDE.md` Rules line naming the table as the only place routing values live, stating that the repository-tree agent and skill copies carry no routing and inherit the session model, and noting that `guard_source_frontmatter` rejects a re-added `model:`, `effort:`, or `thinking:` line.
1.3 In `build.sh`, remove `set_codex_agent_model` and `set_codex_skill_model` and drive both harnesses from the table: inject `model:` and `effort:` after the `description:` line of every Claude and Codex copy, inject `thinking:` after `description:` and strip `color:` for every Pi agent, and leave Pi skills untouched. Derive `PI_AGENT_NAMES` from the table's agent names. Replace the hardcoded Codex routing summary line with a line naming the table.
1.4 Add the build gates to `build.sh`: run the validator self-test, then `routing_load`, `routing_check_coverage`, and `guard_source_frontmatter` before `setup_dirs`, so no failure path writes an artifact. The self-test uses fixtures in a temporary directory (a tab line, an unknown section key, an unknown flow-map key, a quoted value, a row without `file:`) and mirrors `run_guard_self_test`. `guard_source_frontmatter` fails on `model:`, `effort:`, or `thinking:` lines in `.claude/agents/*.md` and `.claude/skills/speq-*/SKILL.md` frontmatter. [expert]
1.5 Emit `dist/marketplace/pi/model-overrides.json` from the table: `{"speq-<agent>": "<model>"}` for every agent whose `pi.model` is not null, in table order, and `{}` when none. Assert in the build that no payload directory contains the table file.
2.1 Extend `install_pi_agents` in `install.sh`: read any existing `$PI_AGENTS_DIR/.speq-model-overrides` marker before the directory is replaced, then read `$MARKETPLACE_DIR/pi/model-overrides.json`. Every install path reconciles: merge `subagents.agentOverrides.<name>.model` for the pinned names into `$HOME/.pi/agent/settings.json`, remove every name the previous marker lists that the current artifact no longer pins, and rewrite the marker to the current set; when the artifact is missing or empty, remove the previous marker's names and rewrite the marker to the new set (empty). Leave `settings.json` untouched only when the artifact pins nothing and no previous marker exists. Create the file when it is absent and at least one model is pinned. Merge with perl and the core `JSON::PP` module: preserve every other key and write only when the serialized document differs. When the document is invalid JSON, warn and leave the file untouched without failing the install. Write through a temporary file plus a rename, so a failed write leaves the original byte-identical. When perl or `JSON::PP` is unavailable, warn and print the JSON to add without writing a marker. [expert]
2.2 Extend `remove_pi_agents` in `uninstall.sh`: read the marker before removing the directory and remove exactly those `agentOverrides` keys, dropping `agentOverrides` and `subagents` when they become empty. Keep every unrelated key. When `settings.json` is absent, remove nothing and do not create it; when the document is invalid JSON, warn and leave the file untouched without failing the uninstall; write through the same temporary file plus rename, so a failed write leaves the original byte-identical. Use perl and the core `JSON::PP` module, the same helper shape as the installer. Keep perl only: the existing python3 and node helpers stay scoped to the legacy Codex marketplace file. When perl or `JSON::PP` is unavailable, warn, list the `subagents.agentOverrides` entries to remove manually, and exit 0 without touching the file.
3.1 Add `scripts/plugin/render-model-routing-docs.sh`: render the three harness tables from the table into marked blocks of a target path, default `docs/model-routing.md`. Add the markers, regenerate the three tables (skills first, then agents; missing or null values render as `inherited`; Pi shows Model and Thinking columns; a skill name renders as `/speq:<name>` for Claude and Codex and `/skill:speq-<name>` for Pi; an agent name renders bare for Claude and Codex and `speq-`-prefixed for Pi), and update the prose: the table is the single source, and the Pi section explains the installer's override behavior. Replace the hand-written "Pin the Pi models" snippet with table-driven instructions plus a short manual-override fallback. The instructions state that a non-null `pi.model` in a row is the way to pin a model: edit the row, rebuild, and reinstall, and the installer reconciles the pinned entries. The fallback keeps the existing `subagents.agentOverrides` JSON snippet, labeled as the operator's manual path, and states that the installer removes only the entries it recorded. Both are hand-written prose outside the generated table blocks and use placeholder ids only, so they cannot drift from the table.
4.1 Add `tests/model_routing.rs`: build the plugin from a temporary copy of `.claude/`, `scripts/`, and `Cargo.toml` so no test writes the repository's `dist/`. Assert each harness's emitted frontmatter including the empty-map case, the four failure paths, the overrides artifact, and that no payload ships the table. Include the docs check: render into a temporary copy and compare with the committed `docs/model-routing.md`.
4.2 Add `tests/pi_model_overrides.rs`: source `install.sh`, and run `uninstall.sh` as a subprocess with `HOME` pointed at a temporary directory and `PATH` restricted to a fake bin directory plus `/usr/bin:/bin`, with fake `claude` and `codex` executables, so the uninstaller's plugin steps cannot reach the operator's real installation (the `tests/install_mcp_servers.rs` pattern). Assert the merge preserves unrelated keys, the no-pin path with no previous marker writes nothing, a payload that drops a pin removes the previous entry and rewrites the marker, an absent file is created when a model is pinned, an invalid document is left untouched with a warning, a failed write leaves the original byte-identical, a second install leaves the file byte-identical, uninstall removes only marked names, uninstall with an absent file removes nothing and does not create it, a failing perl on install warns without writing, and a failing perl on uninstall lists the entries to remove manually and exits 0 without touching the file.
5.1 Verification pass: run the checklist, the manual tests, and the full-tree diff against a build taken before the change.

## Parallelization

| Group | Tasks | Depends on | Knowledge |
|-------|-------|------------|-----------|
| A: routing table, build, and docs | 1.1-1.5, 3.1, 4.1 | — | spec delta `distribution/model-routing`; `scripts/lib/model-routing.sh`, `scripts/plugin/build.sh`, `model-routing.yml`, `scripts/plugin/render-model-routing-docs.sh`, `docs/model-routing.md`, `tests/model_routing.rs` |
| B: installer overrides | 2.1-2.2, 4.2 | — (consumes the artifact contract in `distribution/model-routing`) | spec delta `distribution/pi-model-overrides`; `install.sh`, `uninstall.sh`, `tests/pi_model_overrides.rs` |

## Dead Code Removal

| Type | Location | Reason |
|------|----------|--------|
| Function | `scripts/plugin/build.sh` `set_codex_agent_model` | Replaced by table-driven injection |
| Function | `scripts/plugin/build.sh` `set_codex_skill_model` | Replaced by table-driven injection |
| Constant | `scripts/plugin/build.sh` `PI_AGENT_NAMES` | Derived from the routing table |
| Line | `scripts/plugin/build.sh` `transform_pi_markdown` model and effort deletions | The source guard rejects those lines, so the Pi copy cannot carry them |
| Line | `scripts/plugin/build.sh` `transform_pi_agent` `effort:` rename | Replaced by `thinking:` injection from the table |
| Line | `scripts/plugin/build.sh` `transform_pi_agent` model deletion | The source guard rejects `model:`, so the Pi copy cannot carry it |
| Line | `scripts/plugin/build.sh` final Codex routing summary | Hardcoded values replaced by a pointer to the table |
| Frontmatter | `.claude/agents/*.md` `model:`, `effort:` | Moved to the table |
| Frontmatter | `.claude/skills/speq-*/SKILL.md` `model:` | Moved to the table |

## Verification

### Scenario Coverage

| Scenario | Test Type | Test Location | Test Name |
|----------|-----------|---------------|-----------|
| Build emits Claude routing | Integration | `tests/model_routing.rs` | `build_injects_claude_routing` |
| Build emits Codex routing | Integration | `tests/model_routing.rs` | `build_injects_codex_routing` |
| Build emits Pi reasoning without a model | Integration | `tests/model_routing.rs` | `build_emits_pi_thinking_only` |
| Empty harness map inherits the harness default | Integration | `tests/model_routing.rs` | `build_inherits_on_empty_harness_map` |
| Build rejects syntax outside the subset | Integration | `tests/model_routing.rs` | `build_rejects_out_of_subset_line` |
| Build rejects a source file with no row | Integration | `tests/model_routing.rs` | `build_rejects_missing_routing_row` |
| Build rejects a row with no matching file | Integration | `tests/model_routing.rs` | `build_rejects_row_without_file` |
| Build rejects routing values in source frontmatter | Integration | `tests/model_routing.rs` | `build_rejects_source_frontmatter_routing` |
| Build writes the Pi model overrides artifact | Integration | `tests/model_routing.rs` | `build_writes_pi_model_overrides_artifact` |
| Documentation matches the routing table | Integration | `tests/model_routing.rs` | `docs_match_routing_table` |
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

### Manual Testing

| Feature | Command | Expected Output |
|---------|---------|-----------------|
| distribution/model-routing | `./scripts/plugin/build.sh` | Exit 0; emitted frontmatter matches the table; `dist/marketplace/pi/model-overrides.json` contains `{}` |
| distribution/model-routing | `./scripts/plugin/render-model-routing-docs.sh && git diff --stat docs/model-routing.md` | No diff |
| distribution/model-routing | `diff -r` the built `dist/marketplace` against a copy taken before the change | Identical except the added `pi/model-overrides.json` |
| distribution/pi-model-overrides | `shasum -a 256 ~/.pi/agent/settings.json` before and after `./scripts/local-install.sh` | Same hash, because the shipped table pins no model |
| both | `./target/debug/speq plan validate add-model-routing-table` | Pass |

### Checklist

| Step | Command | Expected |
|------|---------|----------|
| Build | `cargo build --release` | Exit 0 |
| Test | `cargo test` | 0 failures |
| Lint | `cargo fmt && cargo clippy` | 0 errors/warnings |
| Format | `cargo fmt --check` | No changes |
| Plugin build | `./scripts/plugin/build.sh` | Exit 0, guards pass |
