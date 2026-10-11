# Code Review Findings: fix-installer-payload-root

## Summary
- Files reviewed: 4
- Total findings: 5 (standard: 4, expert: 1)

The payload-root fix matches the plan. `install.sh` and `uninstall.sh` default `MARKETPLACE_DIR` with `${MARKETPLACE_DIR:-$HOME/.speq-skill}`, `install_pi_agents` binds the agent source path and the artifact path at call time, the `PI_OVERRIDES_ARTIFACT` global and the late `scripts/local-install.sh` assignment are deleted, and `guard_marketplace_removal_target` rejects `/`, exactly `$HOME`, and unmarked roots before any removal. All 20 integration tests pass, `bash -n` passes for all three shell files, and `rustfmt --check` passes for the test file. The findings below concern the new test harness and one stale comment. The pre-existing version-bump hunks in `install.sh` and `uninstall.sh` are outside this review.

## Standard fixes

### tests/pi_model_overrides.rs

#### [NONDETERMINISTIC_TEST] Installer tests read an ambient MARKETPLACE_DIR
- Location: line 86, `with_isolated_env`
- Issue: `with_isolated_env` clears `CODEX_HOME`, `PERL5LIB`, and `PERL5OPT` but not `MARKETPLACE_DIR`. `install.sh` selects its Pi payload root from `MARKETPLACE_DIR`, so a machine that exports `MARKETPLACE_DIR` and runs `cargo test` decides which payload root every `run_install_function` test reads. Evidence: `MARKETPLACE_DIR=/tmp/ambient-root cargo test --test pi_model_overrides installer_writes_pinned_overrides` fails, because `install_pi_agents` reads `/tmp/ambient-root/pi/agents`, warns `Pi agent payload missing`, and writes no `settings.json`. The module comment states that every run stays isolated from the operator's environment.
- Fix: In tests/pi_model_overrides.rs, add `.env_remove("MARKETPLACE_DIR")` to `with_isolated_env`. Every current test stays correct: `run_uninstaller_with_marketplace` applies its `cmd.env` after `with_isolated_env`, and the split-root test sets the variable with `export` inside the shell command, after the subprocess environment is fixed.

#### [MISSING_BOUNDARY_TEST] No test covers the unset or empty MARKETPLACE_DIR default
- Location: line 102, `run_uninstaller`
- Issue: The requirement defaults `MARKETPLACE_DIR` to `$HOME/.speq-skill` only when it is unset or empty, for both scripts. No test covers those two inputs. `run_uninstaller` delegates to `run_uninstaller_with_marketplace`, which always sets the variable, so every uninstaller test exercises the caller-set path and the `:-` default branch in `uninstall.sh` has no coverage. The installer tests cover the set and unset cases at source time but not the empty string. A regression from `${MARKETPLACE_DIR:-...}` to `${MARKETPLACE_DIR-...}` would pass the whole suite, because the colon is what makes the default apply to an empty value.
- Fix: In tests/pi_model_overrides.rs, add one test named `uninstaller_removes_default_root_when_marketplace_dir_is_unset_or_empty` that seeds a marked default root `$HOME/.speq-skill` plus a second marketplace directory, runs `uninstall.sh` twice, once with `MARKETPLACE_DIR` absent from the command environment (a `Command` configured by `with_isolated_env` with no `cmd.env` call) and once with `MARKETPLACE_DIR` set to the empty string, and asserts that each run exits 0, removes the default root, and retains the second marketplace. In `installer_uses_one_payload_root_for_agents_and_overrides`, add a third block that mirrors block (a) but exports `MARKETPLACE_DIR=''` before sourcing `install.sh`, against a populated default root, and asserts that the default root's agent body and pin win.

#### [SHRINKABLE] Marketplace marker seeding is duplicated at four sites
- Location: lines 157, 847, 885, and 894
- Issue: The marker fixture (a `.claude-plugin` directory holding `marketplace.json` with the content `{}\n`) is created in `mark_marketplace_installed`, which serves only the default root, and three more times inline: for `valid_target` in `uninstaller_guards_marketplace_removal_targets` and for `default_market` and `caller_market` in `uninstaller_honors_marketplace_dir_override`. The rule of three is met, and the fixture content decision is spread across four sites.
- Fix: In tests/pi_model_overrides.rs, add `mark_marketplace_installed_at(root: &Path)` that creates `root/.claude-plugin/marketplace.json` with the content `{}\n`, make `mark_marketplace_installed` delegate to it for the default root, mirroring the existing `install_payload` and `install_payload_fixture_at` pair, and replace the three inline marker creations in `uninstaller_guards_marketplace_removal_targets` and `uninstaller_honors_marketplace_dir_override` with calls to `mark_marketplace_installed_at`.

### scripts/local-install.sh

#### [OUTDATED_COMMENT] Comment states MARKETPLACE_DIR points at the local build
- Location: line 34
- Issue: The comment above the install-function calls states that the functions read `MARKETPLACE_DIR`, which points at the local build. `MARKETPLACE_DIR` defaults to the local build root and carries a caller-provided value when one is set, so the statement does not hold for every run.
- Fix: In scripts/local-install.sh, reword the sentence on line 34 to state that `MARKETPLACE_DIR` defaults to the local build root and may carry a caller-provided value. Leave the rest of the comment unchanged.

## Expert fixes

### tests/pi_model_overrides.rs

#### [NONDETERMINISTIC_TEST] The filesystem-root guard case lets the real rm run against /
- Location: line 780, `uninstaller_guards_marketplace_removal_targets`, the `unsafe_roots` loop
- Issue: The loop runs `uninstall.sh` end to end with `MARKETPLACE_DIR` set to `/`. `guard_marketplace_removal_target` is the only barrier before step 8 runs `rm -rf /`, and the test asserts only after the run completes, so a regressed guard executes the destructive command before any assertion can fail. GNU rm, used on the `ubuntu-latest` CI runners, refuses recursive removal of the filesystem root by default. The rm on macOS has no such failsafe: its man page lists no root protection, and the development machines run macOS. A regressed guard on macOS therefore lets the test delete operator data outside the sandbox. The harness fakes `claude`, `codex`, and `perl` so the script under test cannot reach the operator's system, but the new `/` input reaches that system through the real `rm` in `/bin`.
- Fix: In tests/pi_model_overrides.rs, add an `install_sandbox_rm(dir: &Path)` helper in the existing `install_fake_claude` style that writes an `rm` wrapper into the fake bin: the wrapper checks every argument, executes `/bin/rm "$@"` only when each non-flag argument matches the `case` pattern `"$HOME"/*`, and otherwise prints a refusal that does not name the rejected path and exits 1. The pattern does not match `$HOME` itself, which no expected removal targets. Call `install_sandbox_rm` in `uninstaller_guards_marketplace_removal_targets` and `uninstaller_honors_marketplace_dir_override` before the uninstaller runs. Every removal those tests expect lies under the sandbox `$HOME`, so the existing assertions keep passing. A regressed guard then fails the name-the-directory assertion without deleting anything outside the sandbox, because the wrapper refusal does not echo the path.
