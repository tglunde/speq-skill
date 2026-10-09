# Decision Log: add-model-routing-table

## Interview

**Q1:** What shape should the routing YAML have?
**A:** Row per agent, harness sub-map. One row per agent with `file:`, `note:`, and `claude:`, `codex:`, `pi:` maps. Rejected: flat rows one per agent plus harness; per-harness top-level sections; one file per harness.

**Q2:** What does the YAML own, relative to the `model:`/`effort:` frontmatter already in `.claude/agents/` and `.claude/skills/`?
**A:** YAML owns agents and skills. Remove `model:` and `effort:` from `.claude/agents/*.md` and `.claude/skills/*/SKILL.md`; `build.sh` injects everything from the YAML. One place to edit, no drift possible. Rejected: YAML owns agents only; YAML overlays frontmatter.

**Q3:** On Pi, the build deliberately strips `model:` so no vendor is mandated. Where should a Pi model id from the YAML land?
**A:** Generated settings overrides. `install.sh` writes `subagents.agentOverrides.<name>.model` into `~/.pi/agent/settings.json` from the YAML. Keeps "does not mandate a vendor" true, stays operator-editable, thinking still comes from frontmatter. Rejected: pin the model in Pi agent frontmatter; thinking-only with no Pi model; print a snippet for the operator to paste.

**Q4:** `build.sh` is pure bash and awk with no YAML parser, per the frontmatter-guard precedent. How should it read the YAML?
**A:** Restricted subset, awk-parsed. Constrain the schema to flat key/value plus one level of nesting so awk and sed can read it, and add a build-time validator that fails loudly on anything outside the subset. No new dependency. Rejected: line-oriented block sequence only; adding a `yq` or PyYAML dependency; parsing in the speq Rust binary.

## Design Decisions

### [1] Routing table location: `model-routing.yml` at the repository root

- **Decision:** The table lives at `model-routing.yml` in the repository root, beside the other repository-wide tool config (`Cargo.toml`, `clippy.toml`, `deny.toml`, `rustfmt.toml`, `about.toml`).
- **Alternatives:** `scripts/plugin/model-routing.yml` (the original decision, revised here: it buries a repository-wide routing fact inside the plugin build directory); `.claude/model-routing.yml` (inside the compiled source tree, so it needs an explicit exclusion and blurs the boundary between plugin source and build input).
- **Rationale:** The table governs every agent and skill in the repository, not only the plugin build, so the root is where an author looks for it. The root already holds the repository's tool configuration. The build, the docs renderer, and the tests all reference one path, and the build's payload check keeps the table out of every payload.
- **Consequences:** The table is no longer adjacent to the scripts that read it, so the reader path runs from `CLAUDE.md` and the table's header comment to `scripts/lib/model-routing.sh`. The payload check is load-bearing: the build must still assert that no payload directory contains the table.
- **Promotes to ADR:** no

### [2] Restricted subset parsed by awk, no YAML library

- **Decision:** The table's grammar is a line-oriented subset: section headers, row names, plain properties, and one-level inline maps. A harness map may be empty: `{}` injects nothing and lets the harness inherit its default, while a missing map is an error. The build validates the table and fails on anything outside the subset.
- **Alternatives:** `yq` or PyYAML (a new build dependency); parsing in the Rust binary (couples the plugin build to a cargo build and contradicts the build-time-guard approach recorded in plan 001).
- **Rationale:** Recorded plan 001 rejected a YAML parser for the same scripts tree, and `specs/architecture.md` states "Minimal dependencies to keep maintenance low". The schema needs flat key/value pairs and one nesting level, nothing more.
- **Consequences:** Quoted scalars, block scalars, and nested maps are unavailable by design. A future need extends the grammar and the validator together.
- **Promotes to ADR:** no

### [3] Documentation tables generated from the table

- **Decision:** `docs/model-routing.md` keeps its prose, and its three routing tables are generated from the table by `scripts/plugin/render-model-routing-docs.sh` into marked blocks. An integration test fails when the committed document differs from the rendered output.
- **Alternatives:** hand-written tables with no check (they drift, which is the problem this plan removes); hand-written tables with a consistency check (needs the same rendering logic); deleting the tables and pointing at the YAML (loses the user-facing view).
- **Rationale:** One owner per fact. The build must not rewrite a tracked file, so the renderer is a separate script, and the test makes a stale document a failure instead of a silent drift.
- **Consequences:** Each row carries a `note:` field so the Notes column has a source. Adding a row without a note fails validation. The generator is a manual step; the test catches a missed run.
- **Promotes to ADR:** no

### [4] The build emits a Pi overrides artifact; the installer consumes it

- **Decision:** `build.sh` writes `pi/model-overrides.json` into the Pi payload from the non-null `pi.model` values. `install.sh` reads that file and never parses the table.
- **Alternatives:** ship the table and parse it in `install.sh` (duplicates the parser in a standalone script that cannot source the repository's library); hardcode the ids in `install.sh` (duplicates the table).
- **Rationale:** One parser and one validation point. The installer consumes a generated artifact that the build already validated.
- **Consequences:** An `install.sh` from `main` that runs against an older release payload skips a missing artifact and installs no overrides.
- **Promotes to ADR:** no

### [5] Installer merge with perl and core JSON::PP

- **Decision:** `install.sh` and `uninstall.sh` merge `settings.json` with perl and the core `JSON::PP` module: parse the document, set or remove the named entries, serialize with sorted keys and two-space indent, and write only when the result differs from the file.
- **Alternatives:** python3 or node (outside this plan's allowed toolset for `install.sh`); hand-written awk or perl text surgery on the JSON (fragile, and duplicated in two standalone scripts); `jq` (a new dependency).
- **Rationale:** `JSON::PP` ships with perl since 5.14, so the merge adds no installed dependency, and a wrong edit to an operator-owned file is worse than a formatting change.
- **Consequences:** The first write normalizes key order and formatting; later writes are byte-stable. A missing perl or `JSON::PP` degrades to a printed snippet and no write, so the installer never half-writes the file.
- **Promotes to ADR:** no

### [6] A marker file records the overrides the installer wrote

- **Decision:** `install.sh` records the override names it wrote in `$PI_AGENTS_DIR/.speq-model-overrides`. `uninstall.sh` removes exactly those entries and leaves operator-added ones.
- **Alternatives:** uninstall removes every override whose name matches an installed speq agent (clobbers an operator's manual pin, which the current documentation tells operators to add); uninstall leaves all entries (stale overrides survive the removal).
- **Rationale:** The marker follows the existing `.speq-skill-managed` convention: removal touches only what the installer owns.
- **Consequences:** Reinstall reconciles. A name in the old marker that the new artifact no longer pins is removed.
- **Promotes to ADR:** no

### [7] Spec home: a new `distribution` domain with two features

- **Decision:** The plan adds `distribution/model-routing` and `distribution/pi-model-overrides` as new features under a new `distribution` domain.
- **Alternatives:** no spec home, following recorded plan 001; one combined feature for build and install.
- **Rationale:** `specs/mission.md` capability 14 names the plugin build and the installer, and no feature spec covers it, so the audit's unbacked-capability check flags it today. This plan introduces observable contracts: a validated table format, hard build failures, and merge semantics for an operator file. Recorded plan 001 covered a narrow guard inside one script; this plan introduces a configuration format and cross-script data flow. Two features keep the build contract and the install contract separate, which also gives the two implementation groups distinct spec deltas.
- **Consequences:** Capability 14 gains partial coverage. Future distribution work extends the same domain.
- **Promotes to ADR:** no

### [8] Missing routing data fails the build

- **Decision:** A source agent or skill with no row, a row whose file is absent or misnamed, and a source `model:`, `effort:`, or `thinking:` line each fail the build before it writes an artifact.
- **Alternatives:** warn and emit without routing; treat a missing row as "inherit".
- **Rationale:** Silent inheritance is the drift this plan removes. A hard failure names the file and the fix in one line.
- **Consequences:** Adding an agent or skill requires a table row in the same change. The guard replaces the Pi copy's model and effort deletions, which can no longer trigger.
- **Promotes to ADR:** no

### [9] One routing table owns per-harness model and effort

- **Decision:** Every agent and skill takes its model, effort, and thinking values from one routing table. The source frontmatter carries none of them. The build injects the values into each emitted tree, and the installer propagates the Pi model ids into the operator's Pi settings.
- **Alternatives:** keep the values in the source frontmatter and transform them per harness (the drift this plan removes); parse the table with a YAML library (adds a build dependency).
- **Rationale:** Criterion 2: the table and its restricted grammar bind every future routing change. Criterion 4: the rejected parser alternative matters to a later reader, because the syntax limit is deliberate. `speq decision-log show` lists nine accepted ADRs; none covers model routing, build-time parsing, or the installer's settings contract.
- **Consequences:** One edit point per value. Adding an agent or skill requires a row. `PI_AGENT_NAMES` derives from the table instead of a second hardcoded list. Pi rows pin no model, so the mission's out-of-scope stance, "does not mandate a model or a vendor", still holds.
- **Architecture:** no change: the change is confined to build and install tooling under `scripts/` and the repository root, which `specs/architecture.md` excludes; no CLI component, boundary, interface, or data flow changes.
- **Promotes to ADR:** yes

## Review Findings

### [plan-review] settings.json absent, invalid, or unwritable

- **Finding:** The main scenario assumed the operator's `settings.json` exists; neither the delta nor task 2.1 covered an absent file, an invalid JSON document, or a failed write. An invalid document made `JSON::PP` die under `set -e` after the agents directory was replaced, and a direct write could truncate the file.
- **Direction change:** Added scenarios to `distribution/pi-model-overrides/spec.md` for an absent file (the installer creates it when at least one model is pinned; the uninstaller removes nothing and does not create it), an invalid document (both tools warn and leave it untouched without failing), and a failed write (temporary file plus rename, original byte-identical). Task 2.1 carries the same rules, task 2.2 carries the uninstaller's, the "Operator-owned settings" requirement states them, the scenario coverage table maps the six new tests, and task 4.2 asserts them.
- **Promotes to ADR:** no

### [plan-review] Reconcile every install path

- **Finding:** Task 2.1 said "When the artifact is missing or empty, touch nothing", which contradicted decision [6]. After a reinstall whose new payload pins nothing, the agents directory replacement destroys the old marker, the old settings entries survive, and the uninstaller can never find them again.
- **Direction change:** Rewrote task 2.1 so every install path reconciles: a missing or empty artifact removes the previous marker's names from `settings.json` and rewrites the marker to the current set, and the "MUST NOT modify `settings.json`" guarantee applies only when the artifact pins nothing and no previous marker exists. Added the scenario "Installer removes overrides the previous install recorded but the current payload no longer pins" and qualified the no-pins scenario's GIVEN with "and no previous install recorded overrides"; added the coverage row and the task 4.2 assertion.
- **Promotes to ADR:** no
