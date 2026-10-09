# Planning Hand-off Note: add-model-routing-table

## Files Checked

- `CLAUDE.md`: repo rules, CLI usage, changelog scope, plugin/spec boundary
- `specs/mission.md`: capability 14 (distribute the plugin and the installer), Commands, Tech Stack, Constraints
- `specs/architecture.md`: CLI-only scope; confirms no architecture delta
- `specs/_decision/*.md`: the nine accepted ADRs
- `specs/_recorded/001-fix-skill-frontmatter-guard/`: plan.md, decision-log.md, tasks.md; the closest prior art (build-time guard, no YAML parser)
- `scripts/plugin/build.sh`: full read: transform functions, hardcoded routing lists, guard functions, main flow
- `scripts/lib/version.sh`, `scripts/local-install.sh`, `scripts/release/build.sh`, `scripts/release/test.sh`
- `install.sh`: full read: `install_pi_agents`, payload copy paths, `set -e` behavior
- `uninstall.sh`: full read: `remove_pi_agents`, JSON helper precedent
- `.claude/agents/*.md` (9 files): frontmatter values
- `.claude/skills/*/SKILL.md` (20 files): the six with `model: sonnet`
- `docs/model-routing.md`: the three hand-written tables and the Pi pinning snippet
- `dist/marketplace/{plugins,codex,pi}/`: emitted frontmatter for all three harnesses
- `tests/mcp_config.rs`, `tests/install_mcp_servers.rs`, `tests/install_model_provisioning.rs`, `tests/decision_log_show.rs`: test harness patterns
- `src/plan.rs`, `src/validate/rules.rs`, `src/validate/decision_log.rs`: plan validation rules
- `Cargo.toml`, `Cargo.lock`: serial_test 3.5 without the `file_locks` feature
- `CHANGELOG.md`, `.gitignore`, `README.md`, `docs/index.md`
- `~/.pi/agent/settings.json`, `~/.pi/agent/npm/node_modules/pi-subagents/docs/models.md`: Pi override precedence and file shape

## Searches Run

- `grep` for `gpt-5|opus|sonnet|fable` in `tests/`, `scripts/`, `.github/`: no test pins the model values
- `grep` for `settings.json|agentOverrides` in `install.sh`, `uninstall.sh`, `scripts/`: only a comment in build.sh
- `grep` for `install_pi_agents|PI_AGENTS_DIR`: install.sh and local-install.sh call sites
- `perl -MJSON::PP`: module present (4.06), core since perl 5.14
- JSON::PP round-trip probe: `canonical` + `indent_length(2)` + `space_after` matches Pi's file style; plain hashes randomize key order across processes
- `du -sh .claude scripts`: 324K and 64K, so a temp-root build copy is cheap
- `./target/debug/speq decision-log show`: nine ADRs, none about routing, build parsing, or installer settings
- Spec discovery (`domain list`, `feature list`, `search query`, `decision-log show`): from the orchestrator's Existing Context, not re-run

## ADR Conflict Check

All nine accepted ADRs reviewed: `pure-rust-inference`, `tract-onnx-inference`, `installer-model-provisioning`, `per-plan-decision-fragments`, `slug-identity-not-sequential-numbers`, `parallelize-with-ordered-collect`, `anchor-first-nonempty-line`, `plan-validate-skips-anchor-presence`, `record-all-or-nothing-across-plan`. None covers model routing, build-time parsing, or the installer's settings contract. The promoted entry [9] conforms to `installer-model-provisioning` (the installer may write user state it owns) and does not contradict it.
