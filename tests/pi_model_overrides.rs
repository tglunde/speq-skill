//! Integration tests for the Pi model overrides handling in `install.sh`
//! (`install_pi_agents`) and `uninstall.sh` (`remove_pi_agents`).
//!
//! The installer tests source `install.sh` and invoke `install_pi_agents`
//! directly. `uninstall.sh` has no `BASH_SOURCE` guard, so those tests run it
//! as a subprocess. Every run points `HOME` at a temporary directory and
//! restricts `PATH` to a temp dir of fakes plus `/usr/bin:/bin` only, never
//! the real `PATH`, so the uninstaller's plugin steps cannot reach the
//! operator's installation (the `tests/install_mcp_servers.rs` pattern).
//! The JSON documents live under `tests/fixtures/pi_model_overrides/`.

use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use tempfile::TempDir;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn install_script() -> PathBuf {
    repo_root().join("install.sh")
}

fn uninstall_script() -> PathBuf {
    repo_root().join("uninstall.sh")
}

fn fixture(name: &str) -> PathBuf {
    repo_root()
        .join("tests")
        .join("fixtures")
        .join("pi_model_overrides")
        .join(name)
}

/// A restricted PATH: `dir` first, then only `/usr/bin:/bin`.
fn restricted_path(dir: &Path) -> String {
    format!("{}:/usr/bin:/bin", dir.display())
}

/// Guard against a stale assumption: panics if `cmd` is resolvable on the
/// bare `/usr/bin:/bin` PATH, since that would invalidate any test that
/// relies on `cmd` being absent.
fn assert_absent_from_restricted_path(cmd: &str) {
    let output = Command::new("bash")
        .args(["-c", &format!("command -v {cmd}")])
        .env("PATH", "/usr/bin:/bin")
        .output()
        .expect("run command -v");
    if output.status.success() {
        panic!(
            "'{cmd}' is unexpectedly resolvable on /usr/bin:/bin ({}); \
             this test's absence assumption is invalid on this machine",
            String::from_utf8_lossy(&output.stdout).trim()
        );
    }
}

fn write_executable(path: &Path, contents: &str) {
    fs::write(path, contents).unwrap_or_else(|e| panic!("write {}: {e}", path.display()));
    let mut perms = fs::metadata(path).unwrap().permissions();
    perms.set_mode(0o755);
    fs::set_permissions(path, perms).unwrap_or_else(|e| panic!("chmod {}: {e}", path.display()));
}

/// Fake `claude` that accepts every subcommand, so the uninstaller's plugin
/// steps cannot reach the operator's real installation.
fn install_fake_claude(dir: &Path) {
    write_executable(&dir.join("claude"), "#!/usr/bin/env bash\nexit 0\n");
}

/// Fake `codex` that accepts every subcommand.
fn install_fake_codex(dir: &Path) {
    write_executable(&dir.join("codex"), "#!/usr/bin/env bash\nexit 0\n");
}

/// Fake `rm` that executes the real `/bin/rm` only when every non-flag
/// argument lies under the sandbox `$HOME` (the `"$HOME"/*` pattern does not
/// match `$HOME` itself). Anything else is refused with a message that names
/// no path, so a regressed marketplace guard fails the name-the-directory
/// assertion while the real `rm` — which has no filesystem-root failsafe on
/// macOS — never receives a destructive target outside the sandbox.
fn install_sandbox_rm(dir: &Path) {
    write_executable(
        &dir.join("rm"),
        "#!/usr/bin/env bash\n\
for arg in \"$@\"; do\n\
    case \"$arg\" in\n\
        -*) ;;\n\
        \"$HOME\"/*) ;;\n\
        *) echo \"sandbox rm: refusing an argument outside the sandbox home\" >&2; exit 1 ;;\n\
    esac\n\
done\n\
exec /bin/rm \"$@\"\n",
    );
}

/// Fake `perl` that fails every invocation, simulating a host without perl or
/// without its core JSON::PP module.
fn install_failing_perl(dir: &Path) {
    write_executable(&dir.join("perl"), "#!/usr/bin/env bash\nexit 1\n");
}

fn with_isolated_env(cmd: &mut Command, home: &Path, fake_bin: &Path) {
    cmd.env("HOME", home)
        .env("PATH", restricted_path(fake_bin))
        .env_remove("CODEX_HOME")
        .env_remove("MARKETPLACE_DIR")
        .env_remove("PERL5LIB")
        .env_remove("PERL5OPT");
}

fn run_install_function(home: &Path, fake_bin: &Path, function: &str) -> Output {
    let command = format!("source {} && {function}", install_script().display());
    let mut cmd = Command::new("bash");
    cmd.args(["-c", &command]);
    with_isolated_env(&mut cmd, home, fake_bin);
    cmd.output().expect("run install.sh function")
}

fn run_uninstaller(home: &Path, fake_bin: &Path) -> Output {
    run_uninstaller_with_marketplace(home, fake_bin, &home.join(".speq-skill"))
}

/// Run `uninstall.sh` with `MARKETPLACE_DIR` bound to `marketplace`, so the
/// caller-provided root is the one the uninstaller must honor.
fn run_uninstaller_with_marketplace(home: &Path, fake_bin: &Path, marketplace: &Path) -> Output {
    let mut cmd = Command::new("bash");
    cmd.arg(uninstall_script());
    with_isolated_env(&mut cmd, home, fake_bin);
    cmd.env("MARKETPLACE_DIR", marketplace);
    cmd.output().expect("run uninstall.sh")
}

/// Create the marketplace payload the installer reads at the default root
/// `$HOME/.speq-skill`: `pi/agents` with one managed agent and, when
/// `artifact` is `Some`, the named `pi/model-overrides.json` fixture.
fn install_payload(home: &Path, artifact: Option<&str>) {
    install_payload_fixture_at(&home.join(".speq-skill"), artifact);
}

/// Create the same fixture payload `install_payload` places under the default
/// root at an arbitrary marketplace root.
fn install_payload_fixture_at(root: &Path, artifact: Option<&str>) {
    let agents = root.join("pi/agents");
    fs::create_dir_all(&agents).unwrap();
    fs::copy(
        fixture("agents/speq-planner-agent.md"),
        agents.join("speq-planner-agent.md"),
    )
    .unwrap_or_else(|e| panic!("copy agent fixture: {e}"));
    if let Some(name) = artifact {
        fs::copy(fixture(name), root.join("pi/model-overrides.json"))
            .unwrap_or_else(|e| panic!("copy artifact fixture {name}: {e}"));
    }
}

/// Create a marketplace payload at an arbitrary root whose agent body and pin
/// are distinguishable per root: `pi/agents` with one managed agent whose
/// content is `agent_md`, and a `pi/model-overrides.json` pinning the bare
/// model id `pinned_model` for that agent. Bare model ids skip the
/// provider-configuration gate, so this payload needs no Pi provider files.
fn install_payload_at(root: &Path, agent_md: &str, pinned_model: &str) {
    let agents = root.join("pi/agents");
    fs::create_dir_all(&agents).unwrap();
    fs::write(agents.join("speq-planner-agent.md"), agent_md).unwrap();
    fs::write(
        root.join("pi/model-overrides.json"),
        format!(r#"{{ "speq-planner-agent": "{pinned_model}" }}"#),
    )
    .unwrap();
}

/// Create the install marker every installed marketplace root carries at an
/// arbitrary root, so the uninstaller's removal guard accepts that root as a
/// valid target.
fn mark_marketplace_installed_at(root: &Path) {
    let dir = root.join(".claude-plugin");
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join("marketplace.json"), "{}\n").unwrap();
}

/// Create the install marker at the default root `$HOME/.speq-skill`, so the
/// uninstaller's removal guard accepts it as a valid target.
fn mark_marketplace_installed(home: &Path) {
    mark_marketplace_installed_at(&home.join(".speq-skill"));
}

/// Recreate the managed Pi agent directory a previous install left behind,
/// with the marker that records the overrides it wrote.
fn install_previous_marker(home: &Path, names: &str) {
    let dir = home.join(".pi/agent/agents/speq");
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join(".speq-skill-managed"), "").unwrap();
    fs::write(dir.join(".speq-model-overrides"), names).unwrap();
}

fn write_settings(home: &Path, fixture_name: &str) -> PathBuf {
    let dir = home.join(".pi/agent");
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("settings.json");
    fs::copy(fixture(fixture_name), &path)
        .unwrap_or_else(|e| panic!("copy settings fixture {fixture_name}: {e}"));
    path
}

/// Write a Pi provider configuration file (`auth.json`, `models.json` or
/// `models-store.json`) under the temporary `HOME`.
fn write_pi_config(home: &Path, file_name: &str, fixture_name: &str) -> PathBuf {
    let dir = home.join(".pi/agent");
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join(file_name);
    fs::copy(fixture(fixture_name), &path)
        .unwrap_or_else(|e| panic!("copy {file_name} fixture {fixture_name}: {e}"));
    path
}

fn settings_path(home: &Path) -> PathBuf {
    home.join(".pi/agent/settings.json")
}

fn marker_path(home: &Path) -> PathBuf {
    home.join(".pi/agent/agents/speq/.speq-model-overrides")
}

fn read(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn combined(output: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}

fn assert_success(output: &Output, context: &str) {
    assert!(
        output.status.success(),
        "{context} failed:\n{}",
        combined(output)
    );
}

fn assert_matches_fixture(path: &Path, fixture_name: &str) {
    assert_eq!(
        read(path),
        read(&fixture(fixture_name)),
        "{} does not match fixture {fixture_name}",
        path.display()
    );
}

// ---------------------------------------------------------------------
// install_pi_agents
// ---------------------------------------------------------------------

#[test]
fn installer_writes_pinned_overrides() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_planner.json"));
    write_settings(home.path(), "settings_with_unrelated_keys.json");

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert_matches_fixture(&settings_path(home.path()), "expected_pinned_settings.json");
    assert_eq!(read(&marker_path(home.path())), "speq-planner-agent\n");
}

#[test]
fn installer_creates_absent_settings() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_planner.json"));

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert_matches_fixture(
        &settings_path(home.path()),
        "expected_created_settings.json",
    );
    assert_eq!(read(&marker_path(home.path())), "speq-planner-agent\n");
}

#[test]
fn installer_skips_pins_for_an_unconfigured_provider() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_two_providers.json"));
    write_settings(home.path(), "settings_with_unrelated_keys.json");
    write_pi_config(home.path(), "auth.json", "auth_configured_vendor.json");

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert_matches_fixture(&settings_path(home.path()), "expected_gated_settings.json");

    let out = combined(&output);
    assert!(
        out.contains("speq-code-reviewer") && out.contains("othervendor"),
        "expected a warning naming the skipped agent and its provider, got: {out}"
    );
    assert_eq!(
        read(&marker_path(home.path())),
        "speq-planner-agent\n",
        "the marker must record only the overrides the installer wrote"
    );
}

#[test]
fn installer_writes_a_bare_model_id_without_a_provider_check() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_bare_and_qualified.json"));
    write_settings(home.path(), "settings_with_unrelated_keys.json");
    write_pi_config(home.path(), "auth.json", "auth_configured_vendor.json");

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    let content = read(&settings_path(home.path()));
    assert!(
        content.contains(r#""speq-planner-agent""#)
            && content.contains(r#""model" : "claude-opus-4-6""#),
        "a bare model id names no provider and must be written: {content}"
    );
    assert!(
        !content.contains("speq-code-reviewer"),
        "the qualified pin for an unconfigured provider must be skipped: {content}"
    );
    assert_eq!(read(&marker_path(home.path())), "speq-planner-agent\n");
}

#[test]
fn installer_removes_a_stale_override_for_a_now_unconfigured_provider() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_two_providers.json"));
    write_settings(home.path(), "settings_two_overrides.json");
    write_pi_config(home.path(), "auth.json", "auth_configured_vendor.json");
    install_previous_marker(home.path(), "speq-planner-agent\nspeq-code-reviewer\n");

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    let content = read(&settings_path(home.path()));
    assert!(
        content.contains(r#""model" : "configured-vendor/alpha-model""#),
        "the pin for a configured provider must be written: {content}"
    );
    assert!(
        !content.contains("speq-code-reviewer"),
        "the stale override for an unconfigured provider must be removed: {content}"
    );
    assert!(
        content.contains(r#""operator-agent""#),
        "an operator-written override must survive: {content}"
    );
    assert_eq!(
        read(&marker_path(home.path())),
        "speq-planner-agent\n",
        "the marker must drop the skipped override"
    );
}

#[test]
fn installer_writes_nothing_without_pins() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_empty.json"));

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert!(
        !settings_path(home.path()).exists(),
        "the installer must not create settings.json when nothing is pinned"
    );
    assert!(
        marker_path(home.path()).exists(),
        "the installer must rewrite the marker to the empty set"
    );
    assert_eq!(
        read(&marker_path(home.path())),
        "",
        "the marker must record an empty override set"
    );
}

#[test]
fn installer_removes_unpinned_overrides() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_empty.json"));
    write_settings(home.path(), "settings_with_old_override.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert_matches_fixture(
        &settings_path(home.path()),
        "expected_removed_settings.json",
    );
    assert_eq!(read(&marker_path(home.path())), "");
}

#[test]
fn repeated_install_leaves_settings_unchanged() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_planner.json"));
    write_settings(home.path(), "settings_with_unrelated_keys.json");

    let first = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&first, "first install_pi_agents");
    let path = settings_path(home.path());
    let content = read(&path);
    let inode = fs::metadata(&path).unwrap().ino();

    let second = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&second, "second install_pi_agents");

    assert_eq!(
        read(&path),
        content,
        "a repeated install must not change settings.json"
    );
    assert_eq!(
        fs::metadata(&path).unwrap().ino(),
        inode,
        "a repeated install must not rewrite settings.json"
    );
}

#[test]
fn installer_leaves_invalid_settings_untouched() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_planner.json"));
    let path = write_settings(home.path(), "settings_invalid.json");
    let before = read(&path);

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(
        &output,
        "install_pi_agents must not fail on an invalid settings.json",
    );

    assert_eq!(
        read(&path),
        before,
        "the invalid document must stay byte-identical"
    );
    let out = combined(&output);
    assert!(
        out.contains("is not valid JSON"),
        "expected a warning about the invalid document, got: {out}"
    );
}

#[test]
fn failed_write_leaves_settings_byte_identical() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_pins_planner.json"));
    write_settings(home.path(), "settings_with_unrelated_keys.json");
    // A managed directory is already in place, so replacing the agents only
    // touches ~/.pi/agent/agents; the blocked write is the settings temp file
    // in ~/.pi/agent itself.
    install_previous_marker(home.path(), "speq-planner-agent\n");

    let dir = home.path().join(".pi/agent");
    let original = fs::metadata(&dir).unwrap().permissions();
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o555)).unwrap();
    assert!(
        fs::write(dir.join(".speq-write-probe"), "probe").is_err(),
        "permission bits do not block writes (running as root?); \
         this test needs a non-root user"
    );

    let before = read(&settings_path(home.path()));
    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");

    fs::set_permissions(&dir, original).unwrap();

    assert_success(
        &output,
        "install_pi_agents must not fail when the write fails",
    );
    assert_eq!(
        read(&settings_path(home.path())),
        before,
        "a failed write must leave the original byte-identical"
    );
    let out = combined(&output);
    assert!(
        out.contains("Failed to update"),
        "expected a warning about the failed write, got: {out}"
    );
    let leftovers: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.contains(".speq-tmp"))
        .collect();
    assert!(
        leftovers.is_empty(),
        "a failed write left a temp file behind: {leftovers:?}"
    );
}

#[test]
fn installer_warns_without_json_writer() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_failing_perl(fake_bin.path());
    install_payload(home.path(), Some("artifact_pins_planner.json"));
    let path = write_settings(home.path(), "settings_with_unrelated_keys.json");
    let before = read(&path);

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert_eq!(read(&path), before, "no write without a JSON writer");
    let out = combined(&output);
    assert!(
        out.contains("perl with JSON::PP is unavailable"),
        "expected a degradation warning, got: {out}"
    );
    assert!(
        out.contains("\"speq-planner-agent\": { \"model\": \"claude-opus-4-6\" }"),
        "the printed snippet must name the pinned override, got: {out}"
    );
    assert!(
        !marker_path(home.path()).exists(),
        "the installer must not record overrides it did not write"
    );
}

#[test]
fn installer_skips_a_malformed_artifact() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_payload(home.path(), Some("artifact_malformed.json"));
    let path = write_settings(home.path(), "settings_with_old_override.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");
    let before = read(&path);

    let output = run_install_function(home.path(), fake_bin.path(), "install_pi_agents");
    assert_success(&output, "install_pi_agents");

    assert_eq!(
        read(&path),
        before,
        "a malformed artifact must not rewrite settings.json"
    );
    assert!(
        combined(&output).contains("Unrecognized Pi model overrides artifact"),
        "expected a warning about the malformed artifact, got: {}",
        combined(&output)
    );
}

/// The agent files and the model-overrides pins must come from one current
/// `MARKETPLACE_DIR`, resolved when `install_pi_agents` runs, not when
/// `install.sh` was sourced. Two independent bash invocations cover the two
/// ways the root changes between source time and call time.
#[test]
fn installer_uses_one_payload_root_for_agents_and_overrides() {
    // (a) The caller exports MARKETPLACE_DIR before install.sh is sourced:
    // the caller root must win over the populated $HOME/.speq-skill default.
    {
        let home = TempDir::new().unwrap();
        let fake_bin = TempDir::new().unwrap();
        install_payload_at(
            &home.path().join(".speq-skill"),
            "default root agent body\n",
            "default-root-model",
        );
        let caller_root = TempDir::new().unwrap();
        install_payload_at(
            caller_root.path(),
            "caller root agent body\n",
            "caller-root-model",
        );

        let command = format!(
            "export MARKETPLACE_DIR='{}' && source {} && install_pi_agents",
            caller_root.path().display(),
            install_script().display()
        );
        let mut cmd = Command::new("bash");
        cmd.args(["-c", &command]);
        with_isolated_env(&mut cmd, home.path(), fake_bin.path());
        let output = cmd
            .output()
            .expect("run install.sh with exported MARKETPLACE_DIR");
        assert_success(&output, "install_pi_agents with exported MARKETPLACE_DIR");

        let installed_agent = home
            .path()
            .join(".pi/agent/agents/speq/speq-planner-agent.md");
        assert_eq!(
            read(&installed_agent),
            "caller root agent body\n",
            "the agent file must come from the caller's payload root"
        );
        let settings = read(&settings_path(home.path()));
        assert!(
            settings.contains("caller-root-model"),
            "the pin from the caller's payload root must win: {settings}"
        );
        assert!(
            !settings.contains("default-root-model"),
            "the default root's pin must not be written: {settings}"
        );
    }

    // (b) MARKETPLACE_DIR is unset while install.sh is sourced, so the
    // default root resolves first; the test then assigns the installing root
    // before install_pi_agents runs. The agent file and the pin must both
    // come from the installing root, and the default root's pin must be
    // ignored. The old source-time artifact wiring fails here: it keeps the
    // default root's pin while the agent file already comes from the new
    // root.
    {
        let home = TempDir::new().unwrap();
        let fake_bin = TempDir::new().unwrap();
        install_payload_at(
            &home.path().join(".speq-skill"),
            "default root agent body\n",
            "default-root-model",
        );
        let installing_root = TempDir::new().unwrap();
        install_payload_at(
            installing_root.path(),
            "installing root agent body\n",
            "installing-root-model",
        );

        let command = format!(
            "source {} && export MARKETPLACE_DIR='{}' && install_pi_agents",
            install_script().display(),
            installing_root.path().display()
        );
        let mut cmd = Command::new("bash");
        cmd.args(["-c", &command]);
        with_isolated_env(&mut cmd, home.path(), fake_bin.path());
        let output = cmd
            .output()
            .expect("run install.sh with late MARKETPLACE_DIR");
        assert_success(&output, "install_pi_agents with late MARKETPLACE_DIR");

        let installed_agent = home
            .path()
            .join(".pi/agent/agents/speq/speq-planner-agent.md");
        assert_eq!(
            read(&installed_agent),
            "installing root agent body\n",
            "the agent file must come from the installing payload root"
        );
        let settings = read(&settings_path(home.path()));
        assert!(
            settings.contains("installing-root-model"),
            "the pin from the installing payload root must win: {settings}"
        );
        assert!(
            !settings.contains("default-root-model"),
            "the default root's pin must be ignored: {settings}"
        );
    }

    // (c) MARKETPLACE_DIR is exported as the empty string before install.sh
    // is sourced. `${MARKETPLACE_DIR:-...}` must treat the empty value like
    // an unset one and resolve to the populated default root, so its agent
    // body and pin win. A regression to `${MARKETPLACE_DIR-...}` keeps the
    // empty value and fails here.
    {
        let home = TempDir::new().unwrap();
        let fake_bin = TempDir::new().unwrap();
        install_payload_at(
            &home.path().join(".speq-skill"),
            "default root agent body\n",
            "default-root-model",
        );

        let command = format!(
            "export MARKETPLACE_DIR='' && source {} && install_pi_agents",
            install_script().display()
        );
        let mut cmd = Command::new("bash");
        cmd.args(["-c", &command]);
        with_isolated_env(&mut cmd, home.path(), fake_bin.path());
        let output = cmd
            .output()
            .expect("run install.sh with empty exported MARKETPLACE_DIR");
        assert_success(
            &output,
            "install_pi_agents with empty exported MARKETPLACE_DIR",
        );

        let installed_agent = home
            .path()
            .join(".pi/agent/agents/speq/speq-planner-agent.md");
        assert_eq!(
            read(&installed_agent),
            "default root agent body\n",
            "an empty MARKETPLACE_DIR must resolve to the default payload root"
        );
        let settings = read(&settings_path(home.path()));
        assert!(
            settings.contains("default-root-model"),
            "the pin from the default payload root must win: {settings}"
        );
    }
}

// ---------------------------------------------------------------------
// remove_pi_agents
// ---------------------------------------------------------------------

#[test]
fn uninstall_removes_only_marked_overrides() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    assert_absent_from_restricted_path("claude");
    assert_absent_from_restricted_path("codex");
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    mark_marketplace_installed(home.path());
    write_settings(home.path(), "settings_two_overrides.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");

    let output = run_uninstaller(home.path(), fake_bin.path());
    assert_success(&output, "uninstall.sh");

    assert_matches_fixture(
        &settings_path(home.path()),
        "expected_uninstall_kept_operator.json",
    );
    assert!(
        !home.path().join(".pi/agent/agents/speq").exists(),
        "the uninstaller must remove the managed Pi agent directory"
    );
}

#[test]
fn uninstaller_drops_empty_parent_objects() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    mark_marketplace_installed(home.path());
    write_settings(home.path(), "settings_with_old_override.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");

    let output = run_uninstaller(home.path(), fake_bin.path());
    assert_success(&output, "uninstall.sh");

    assert_matches_fixture(
        &settings_path(home.path()),
        "expected_removed_settings.json",
    );
}

#[test]
fn uninstaller_noop_without_settings() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    mark_marketplace_installed(home.path());
    install_previous_marker(home.path(), "speq-planner-agent\n");

    let output = run_uninstaller(home.path(), fake_bin.path());
    assert_success(&output, "uninstall.sh");

    assert!(
        !settings_path(home.path()).exists(),
        "the uninstaller must not create settings.json"
    );
}

#[test]
fn uninstaller_leaves_invalid_settings_untouched() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    mark_marketplace_installed(home.path());
    let path = write_settings(home.path(), "settings_invalid.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");
    let before = read(&path);

    let output = run_uninstaller(home.path(), fake_bin.path());
    assert_success(
        &output,
        "uninstall.sh must not fail on an invalid settings.json",
    );

    assert_eq!(
        read(&path),
        before,
        "the invalid document must stay byte-identical"
    );
    let out = combined(&output);
    assert!(
        out.contains("is not valid JSON"),
        "expected a warning about the invalid document, got: {out}"
    );
}

#[test]
fn uninstaller_warns_without_json_writer() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    assert_absent_from_restricted_path("claude");
    assert_absent_from_restricted_path("codex");
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    install_failing_perl(fake_bin.path());
    mark_marketplace_installed(home.path());
    let path = write_settings(home.path(), "settings_two_overrides.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");
    let before = read(&path);

    let output = run_uninstaller(home.path(), fake_bin.path());
    assert_success(&output, "uninstall.sh must exit 0 without a JSON writer");

    assert_eq!(read(&path), before, "no write without a JSON writer");
    let out = combined(&output);
    assert!(
        out.contains("subagents.agentOverrides.speq-planner-agent"),
        "the warning must list the entry to remove manually, got: {out}"
    );
}

/// The uninstaller must reject destructive removal targets before removing
/// anything: `/`, exactly `$HOME`, and any directory without the install
/// marker `.claude-plugin/marketplace.json`. Each rejection exits non-zero,
/// names the rejected directory, and leaves the target intact. A valid
/// marked target still uninstalls and is removed, while a second marketplace
/// directory is retained.
#[test]
fn uninstaller_guards_marketplace_removal_targets() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    assert_absent_from_restricted_path("claude");
    assert_absent_from_restricted_path("codex");
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    install_sandbox_rm(fake_bin.path());

    // Sentinels that prove no rejected run removed anything: the CLI binary,
    // a probe file under HOME, and a populated default marketplace root.
    let install_dir = home.path().join(".local/bin");
    fs::create_dir_all(&install_dir).unwrap();
    fs::write(install_dir.join("speq"), "fake speq binary").unwrap();
    fs::write(home.path().join("home-sentinel.txt"), "keep me").unwrap();
    let default_market = home.path().join(".speq-skill");
    fs::create_dir_all(&default_market).unwrap();
    fs::write(default_market.join("default-sentinel.txt"), "keep me").unwrap();

    let unmarked_target = TempDir::new().unwrap();
    fs::write(
        unmarked_target.path().join("target-sentinel.txt"),
        "keep me",
    )
    .unwrap();

    let unsafe_roots: Vec<(&str, PathBuf)> = vec![
        ("filesystem root", PathBuf::from("/")),
        ("home directory", home.path().to_path_buf()),
        ("unmarked directory", unmarked_target.path().to_path_buf()),
    ];

    for (label, target) in &unsafe_roots {
        let output = run_uninstaller_with_marketplace(home.path(), fake_bin.path(), target);
        assert!(
            !output.status.success(),
            "uninstall.sh must exit non-zero when MARKETPLACE_DIR is the {label}: {}",
            combined(&output)
        );
        let out = combined(&output);
        let quoted = format!("'{}'", target.display());
        assert!(
            out.contains(&quoted),
            "the rejection must name the rejected directory {quoted}, got: {out}"
        );
    }

    // Nothing was removed by any of the rejected runs.
    assert!(
        install_dir.join("speq").exists(),
        "the guard must reject before removing the CLI binary"
    );
    assert!(
        home.path().join("home-sentinel.txt").exists(),
        "the guard must reject before removing anything under HOME"
    );
    assert!(
        unmarked_target.path().join("target-sentinel.txt").exists(),
        "an unmarked target must remain intact"
    );
    assert!(
        default_market.join("default-sentinel.txt").exists(),
        "the default marketplace root must remain intact"
    );

    // A valid, marked target uninstalls cleanly and is removed, while a
    // second marketplace directory is retained.
    let valid_target = home.path().join("valid-marketplace");
    mark_marketplace_installed_at(&valid_target);
    let kept_market = home.path().join("kept-marketplace");
    fs::create_dir_all(&kept_market).unwrap();
    fs::write(kept_market.join("kept-sentinel.txt"), "keep me").unwrap();

    let output = run_uninstaller_with_marketplace(home.path(), fake_bin.path(), &valid_target);
    assert_success(&output, "uninstall.sh with a marked marketplace target");

    assert!(
        !valid_target.exists(),
        "the marked marketplace directory must be removed"
    );
    assert!(
        kept_market.join("kept-sentinel.txt").exists(),
        "a second marketplace directory must be retained"
    );
    assert!(
        default_market.join("default-sentinel.txt").exists(),
        "the default marketplace root must be retained"
    );
}

/// A caller-provided `MARKETPLACE_DIR` governs the uninstaller's marketplace
/// removal: the named directory is removed and the populated default root
/// `$HOME/.speq-skill` is retained. The pre-fix uninstaller ignored the
/// variable and always removed the default root, so the default root here is
/// populated and must survive.
#[test]
fn uninstaller_honors_marketplace_dir_override() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    assert_absent_from_restricted_path("claude");
    assert_absent_from_restricted_path("codex");
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    install_sandbox_rm(fake_bin.path());

    let default_market = home.path().join(".speq-skill");
    mark_marketplace_installed_at(&default_market);
    fs::write(default_market.join("default-sentinel.txt"), "keep me").unwrap();

    let caller_market = home.path().join("caller-marketplace");
    mark_marketplace_installed_at(&caller_market);

    let output = run_uninstaller_with_marketplace(home.path(), fake_bin.path(), &caller_market);
    assert_success(
        &output,
        "uninstall.sh with a caller-provided MARKETPLACE_DIR",
    );

    assert!(
        !caller_market.exists(),
        "the caller-provided marketplace directory must be removed"
    );
    assert!(
        default_market.join("default-sentinel.txt").exists(),
        "the default marketplace directory must not be removed"
    );
}

/// An unset or empty `MARKETPLACE_DIR` must resolve to the default root
/// `$HOME/.speq-skill` for the uninstaller too: each run exits 0, removes
/// the seeded default root, and retains a second marketplace directory.
#[test]
fn uninstaller_removes_default_root_when_marketplace_dir_is_unset_or_empty() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());

    let kept_market = home.path().join("second-marketplace");
    fs::create_dir_all(&kept_market).unwrap();
    fs::write(kept_market.join("kept-sentinel.txt"), "keep me").unwrap();

    // Run 1: MARKETPLACE_DIR absent from the command environment.
    mark_marketplace_installed(home.path());
    fs::write(
        home.path().join(".speq-skill/default-sentinel.txt"),
        "remove me",
    )
    .unwrap();

    let mut cmd = Command::new("bash");
    cmd.arg(uninstall_script());
    with_isolated_env(&mut cmd, home.path(), fake_bin.path());
    let output = cmd
        .output()
        .expect("run uninstall.sh with MARKETPLACE_DIR unset");
    assert_success(&output, "uninstall.sh with MARKETPLACE_DIR unset");

    assert!(
        !home.path().join(".speq-skill").exists(),
        "an unset MARKETPLACE_DIR must resolve to the default root and remove it"
    );
    assert!(
        kept_market.join("kept-sentinel.txt").exists(),
        "a second marketplace directory must be retained"
    );

    // Run 2: MARKETPLACE_DIR set to the empty string.
    mark_marketplace_installed(home.path());
    fs::write(
        home.path().join(".speq-skill/default-sentinel.txt"),
        "remove me",
    )
    .unwrap();

    let mut cmd = Command::new("bash");
    cmd.arg(uninstall_script());
    with_isolated_env(&mut cmd, home.path(), fake_bin.path());
    cmd.env("MARKETPLACE_DIR", "");
    let output = cmd
        .output()
        .expect("run uninstall.sh with empty MARKETPLACE_DIR");
    assert_success(&output, "uninstall.sh with empty MARKETPLACE_DIR");

    assert!(
        !home.path().join(".speq-skill").exists(),
        "an empty MARKETPLACE_DIR must resolve to the default root and remove it"
    );
    assert!(
        kept_market.join("kept-sentinel.txt").exists(),
        "a second marketplace directory must be retained"
    );
}

/// An absent `MARKETPLACE_DIR` is not an unsafe target: the uninstaller
/// warns and names the directory, skips only the marketplace-removal step,
/// and completes the remaining steps with exit status 0.
#[test]
fn uninstaller_skips_absent_marketplace_dir() {
    let home = TempDir::new().unwrap();
    let fake_bin = TempDir::new().unwrap();
    assert_absent_from_restricted_path("claude");
    assert_absent_from_restricted_path("codex");
    install_fake_claude(fake_bin.path());
    install_fake_codex(fake_bin.path());
    install_sandbox_rm(fake_bin.path());

    // The remaining steps must still run, so seed the state each one removes:
    // the CLI binary, a managed Codex skill, a managed Agent Skill, and the
    // managed Pi agent directory with a recorded settings override.
    let install_dir = home.path().join(".local/bin");
    fs::create_dir_all(&install_dir).unwrap();
    fs::write(install_dir.join("speq"), "fake speq binary").unwrap();
    let codex_skill = home.path().join(".codex/skills/speq-test");
    fs::create_dir_all(&codex_skill).unwrap();
    fs::write(codex_skill.join(".speq-skill-managed"), "").unwrap();
    let agents_skill = home.path().join(".agents/skills/speq-test");
    fs::create_dir_all(&agents_skill).unwrap();
    fs::write(agents_skill.join(".speq-skill-managed"), "").unwrap();
    write_settings(home.path(), "settings_with_old_override.json");
    install_previous_marker(home.path(), "speq-planner-agent\n");

    let kept_market = home.path().join("second-marketplace");
    fs::create_dir_all(&kept_market).unwrap();
    fs::write(kept_market.join("kept-sentinel.txt"), "keep me").unwrap();

    let absent_marketplace = home.path().join("absent-marketplace");
    assert!(!absent_marketplace.exists());

    let output =
        run_uninstaller_with_marketplace(home.path(), fake_bin.path(), &absent_marketplace);
    assert_success(
        &output,
        "uninstall.sh must exit 0 when the marketplace directory is absent",
    );

    let out = combined(&output);
    let name = absent_marketplace.display().to_string();
    assert!(
        out.contains(&name) && out.contains("not found"),
        "the warning must name the absent directory, got: {out}"
    );
    assert!(
        !install_dir.join("speq").exists(),
        "the CLI binary removal step must still run"
    );
    assert!(
        !codex_skill.exists(),
        "the Codex skills removal step must still run"
    );
    assert!(
        !agents_skill.exists(),
        "the Agent Skills removal step must still run"
    );
    assert!(
        !home.path().join(".pi/agent/agents/speq").exists(),
        "the Pi sub-agents removal step must still run"
    );
    assert_matches_fixture(
        &settings_path(home.path()),
        "expected_removed_settings.json",
    );
    assert!(
        kept_market.join("kept-sentinel.txt").exists(),
        "a second marketplace directory must be retained"
    );
}
