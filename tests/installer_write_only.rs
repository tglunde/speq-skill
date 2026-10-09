//! Integration tests for the write-only rule in `install.sh`: the installer
//! merges its payloads over the existing tree and removes nothing.
//!
//! These tests source `install.sh`, point `HOME` at a temporary directory, and
//! restrict `PATH` to a temp dir plus `/usr/bin:/bin` only, so no real tool on
//! the host can leak in (the `tests/install_mcp_servers.rs` pattern).

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use tempfile::TempDir;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn install_script() -> PathBuf {
    repo_root().join("install.sh")
}

/// A restricted PATH: `dir` first, then only `/usr/bin:/bin`.
fn restricted_path(dir: &Path) -> String {
    format!("{}:/usr/bin:/bin", dir.display())
}

fn write(path: &Path, contents: &str) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, contents).unwrap_or_else(|e| panic!("write {}: {e}", path.display()));
}

fn run_install_function(home: &Path, function: &str) -> Output {
    let command = format!("source {} && {function}", install_script().display());
    Command::new("bash")
        .args(["-c", &command])
        .env("HOME", home)
        .env("PATH", restricted_path(&home.join("fake-bin")))
        .env_remove("CODEX_HOME")
        .env_remove("SPEQ_LOCAL_TARBALL")
        .output()
        .expect("run install.sh function")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).to_string()
}

/// The Agent Skills payload the installer reads: one skill named `speq-demo`
/// holding a `SKILL.md` and a `references/` file.
fn agents_payload(home: &Path) {
    let root = home.join(".speq-skill/pi/skills/speq-demo");
    write(&root.join("SKILL.md"), "# demo payload\n");
    write(&root.join("references/detail.md"), "# payload detail\n");
}

/// A managed install of `speq-demo`, with a file the operator added.
fn managed_agents_skill(home: &Path) {
    let root = home.join(".agents/skills/speq-demo");
    write(&root.join("SKILL.md"), "# stale payload\n");
    write(&root.join(".speq-skill-managed"), "");
    write(&root.join("operator-notes.md"), "# my notes\n");
}

#[test]
fn agents_skills_merge_preserves_operator_files() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    agents_payload(home);
    managed_agents_skill(home);

    let output = run_install_function(home, "install_agents_skills");
    assert!(
        output.status.success(),
        "installer failed: {}",
        stdout(&output)
    );

    let root = home.join(".agents/skills/speq-demo");
    assert_eq!(
        fs::read_to_string(root.join("SKILL.md")).unwrap(),
        "# demo payload\n",
        "the payload did not overwrite the stale skill"
    );
    assert!(
        root.join("references/detail.md").is_file(),
        "the payload's nested file was not written"
    );
    assert_eq!(
        fs::read_to_string(root.join("operator-notes.md")).unwrap(),
        "# my notes\n",
        "an operator file inside a managed skill was deleted"
    );
}

#[test]
fn agents_skills_merge_keeps_files_the_payload_no_longer_ships() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    agents_payload(home);
    managed_agents_skill(home);
    // A file an earlier release shipped and this one dropped.
    write(
        &home.join(".agents/skills/speq-demo/retired.md"),
        "# retired\n",
    );

    let output = run_install_function(home, "install_agents_skills");
    assert!(
        output.status.success(),
        "installer failed: {}",
        stdout(&output)
    );

    assert!(
        home.join(".agents/skills/speq-demo/retired.md").is_file(),
        "the installer deleted a file the payload no longer ships"
    );
}

#[test]
fn agents_skills_leave_unmanaged_directories_alone() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    agents_payload(home);
    // The same name, written by the operator and carrying no marker.
    write(&home.join(".agents/skills/speq-demo/SKILL.md"), "# mine\n");

    let output = run_install_function(home, "install_agents_skills");
    assert!(
        output.status.success(),
        "installer failed: {}",
        stdout(&output)
    );

    let root = home.join(".agents/skills/speq-demo");
    assert_eq!(
        fs::read_to_string(root.join("SKILL.md")).unwrap(),
        "# mine\n",
        "the installer overwrote an unmanaged directory"
    );
    assert!(
        !root.join(".speq-skill-managed").exists(),
        "the installer claimed an unmanaged directory"
    );
    assert!(
        stdout(&output).contains("not managed by speq-skill"),
        "expected a skip warning, got:\n{}",
        stdout(&output)
    );
}

#[test]
fn agents_skills_leave_symlinks_alone() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    agents_payload(home);
    let elsewhere = home.join("elsewhere");
    write(&elsewhere.join("SKILL.md"), "# elsewhere\n");
    let link = home.join(".agents/skills/speq-demo");
    fs::create_dir_all(link.parent().unwrap()).unwrap();
    std::os::unix::fs::symlink(&elsewhere, &link).unwrap();

    let output = run_install_function(home, "install_agents_skills");
    assert!(
        output.status.success(),
        "installer failed: {}",
        stdout(&output)
    );

    assert!(
        fs::symlink_metadata(&link)
            .unwrap()
            .file_type()
            .is_symlink(),
        "the installer replaced a symlink"
    );
    assert_eq!(
        fs::read_to_string(elsewhere.join("SKILL.md")).unwrap(),
        "# elsewhere\n",
        "the installer wrote through a symlink"
    );
}

#[test]
fn pi_agents_merge_preserves_operator_files() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    let payload = home.join(".speq-skill/pi/agents");
    write(
        &payload.join("speq-demo-agent.md"),
        "name: speq-demo-agent\n",
    );
    let installed = home.join(".pi/agent/agents/speq");
    write(&installed.join("speq-demo-agent.md"), "name: stale\n");
    write(&installed.join(".speq-skill-managed"), "");
    write(
        &installed.join("speq-mine-agent.md"),
        "name: speq-mine-agent\n",
    );

    let output = run_install_function(home, "install_pi_agents");
    assert!(
        output.status.success(),
        "installer failed: {}",
        stdout(&output)
    );

    assert_eq!(
        fs::read_to_string(installed.join("speq-demo-agent.md")).unwrap(),
        "name: speq-demo-agent\n",
        "the payload did not overwrite the stale agent"
    );
    assert!(
        installed.join("speq-mine-agent.md").is_file(),
        "the installer deleted an agent the operator wrote"
    );
}

#[test]
fn merge_tree_overwrites_payload_files_and_removes_nothing() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    let src = home.join("payload");
    write(&src.join("plugins/speq-skill/plugin.json"), "new\n");
    write(&src.join("hidden/.keep"), "hidden\n");
    let dest = home.join(".speq-skill");
    write(&dest.join("plugins/speq-skill/plugin.json"), "old\n");
    write(&dest.join("operator-note.md"), "# keep\n");
    write(&dest.join("retired/old.md"), "# retired\n");

    let output = run_install_function(
        home,
        &format!("merge_tree {} {}", src.display(), dest.display()),
    );
    assert!(
        output.status.success(),
        "merge_tree failed: {}",
        stdout(&output)
    );

    assert_eq!(
        fs::read_to_string(dest.join("plugins/speq-skill/plugin.json")).unwrap(),
        "new\n",
        "merge_tree did not overwrite an existing file"
    );
    assert!(
        dest.join("hidden/.keep").is_file(),
        "merge_tree did not copy a dot-directory"
    );
    assert!(
        dest.join("operator-note.md").is_file(),
        "merge_tree deleted an operator file"
    );
    assert!(
        dest.join("retired/old.md").is_file(),
        "merge_tree deleted a file the payload no longer ships"
    );
}

#[test]
fn merge_tree_creates_an_absent_destination() {
    let tmp = TempDir::new().unwrap();
    let home = tmp.path();
    fs::create_dir_all(home.join("fake-bin")).unwrap();
    let src = home.join("payload");
    write(&src.join("plugin.json"), "new\n");
    let dest = home.join("nested/deeper/marketplace");

    let output = run_install_function(
        home,
        &format!("merge_tree {} {}", src.display(), dest.display()),
    );
    assert!(
        output.status.success(),
        "merge_tree failed: {}",
        stdout(&output)
    );
    assert_eq!(
        fs::read_to_string(dest.join("plugin.json")).unwrap(),
        "new\n"
    );
}
