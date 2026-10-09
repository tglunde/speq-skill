//! Integration tests for the release-archive completeness check in
//! `install.sh` (`archive_missing_paths` and `install_from_prebuilt`).
//!
//! A release archive built before a payload was added still downloads and
//! extracts cleanly, so the installer must refuse it instead of replacing the
//! operator's install and then reporting success. These tests source
//! `install.sh`, point `HOME` at a temporary directory, and restrict `PATH` to
//! a temp dir of fakes plus `/usr/bin:/bin` only, so no real tool on the host
//! can leak in (the `tests/install_mcp_servers.rs` pattern).

use std::fs;
use std::os::unix::fs::PermissionsExt;
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

fn write_executable(path: &Path, contents: &str) {
    fs::write(path, contents).unwrap_or_else(|e| panic!("write {}: {e}", path.display()));
    let mut perms = fs::metadata(path).unwrap().permissions();
    perms.set_mode(0o755);
    fs::set_permissions(path, perms).unwrap_or_else(|e| panic!("chmod {}: {e}", path.display()));
}

/// The platform slug `install.sh` derives its asset name from. Reusing the
/// script's own `detect_platform` keeps the fixture archive named for whatever
/// platform the test runs on.
fn platform() -> String {
    let output = Command::new("bash")
        .args([
            "-c",
            &format!("source {} && detect_platform", install_script().display()),
        ])
        .output()
        .expect("run detect_platform");
    let slug = String::from_utf8_lossy(&output.stdout).trim().to_string();
    assert!(!slug.is_empty(), "detect_platform returned no platform");
    slug
}

/// Fake `curl` that ignores the URL and copies `$FAKE_ARCHIVE` to the `-o`
/// target, so `install_from_prebuilt` reads a controlled archive.
fn install_fake_curl(dir: &Path) {
    write_executable(
        &dir.join("curl"),
        r#"#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$out" ]] || exit 1
cp "$FAKE_ARCHIVE" "$out"
"#,
    );
}

fn run_install_function(home: &Path, fake_bin: &Path, snippet: &str) -> Output {
    let command = format!("source {} && {snippet}", install_script().display());
    Command::new("bash")
        .args(["-c", &command])
        .env("HOME", home)
        .env("PATH", restricted_path(fake_bin))
        .env_remove("SPEQ_LOCAL_TARBALL")
        .output()
        .expect("run install.sh function")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).to_string()
}

/// Every path `install.sh` requires, so a test can build a complete archive.
const COMPLETE: &[&str] = &[
    "bin/speq",
    ".claude-plugin/marketplace.json",
    "plugins/speq-skill",
    "codex/.agents/plugins/marketplace.json",
    "codex/plugins/speq-skill",
    "pi/skills",
    "pi/agents",
];

/// Create a marketplace tree holding exactly `paths`, then tar it as
/// `speq-marketplace-<version>-<platform>/`.
fn archive_with(paths: &[&str], version: &str, dir: &Path) -> PathBuf {
    let root_name = format!("speq-marketplace-{version}-{}", platform());
    let staging = dir.join("staging");
    let root = staging.join(&root_name);
    for path in paths {
        let full = root.join(path);
        if path.ends_with(".json") || path.ends_with("/speq") {
            fs::create_dir_all(full.parent().unwrap()).unwrap();
            fs::write(&full, b"stub").unwrap();
        } else {
            fs::create_dir_all(&full).unwrap();
        }
    }
    let archive = dir.join("release.tar.gz");
    let status = Command::new("tar")
        .args(["-czf"])
        .arg(&archive)
        .args(["-C"])
        .arg(&staging)
        .arg(&root_name)
        .status()
        .expect("run tar");
    assert!(status.success(), "tar failed");
    archive
}

/// A marketplace tree on disk holding every required path.
fn complete_tree(dir: &Path) -> PathBuf {
    let root = dir.join("marketplace");
    for path in COMPLETE {
        fs::create_dir_all(root.join(path)).unwrap();
    }
    root
}

#[test]
fn complete_archive_reports_nothing_missing() {
    let tmp = TempDir::new().unwrap();
    let fake_bin = tmp.path().join("bin");
    fs::create_dir_all(&fake_bin).unwrap();
    let root = complete_tree(tmp.path());

    let output = run_install_function(
        tmp.path(),
        &fake_bin,
        &format!("archive_missing_paths {}", root.display()),
    );

    assert!(
        output.status.success(),
        "archive_missing_paths failed: {}",
        stdout(&output)
    );
    assert_eq!(
        stdout(&output),
        "",
        "a complete archive must report nothing missing"
    );
}

#[test]
fn archive_reports_every_missing_payload_path() {
    let tmp = TempDir::new().unwrap();
    let fake_bin = tmp.path().join("bin");
    fs::create_dir_all(&fake_bin).unwrap();
    let root = complete_tree(tmp.path());
    fs::remove_dir_all(root.join("pi/skills")).unwrap();
    fs::remove_dir_all(root.join("pi/agents")).unwrap();

    let output = run_install_function(
        tmp.path(),
        &fake_bin,
        &format!("archive_missing_paths {}", root.display()),
    );

    assert_eq!(stdout(&output), "pi/skills\npi/agents\n");
}

#[test]
fn prebuilt_install_refuses_an_archive_that_predates_the_installer() {
    let tmp = TempDir::new().unwrap();
    let fake_bin = tmp.path().join("bin");
    fs::create_dir_all(&fake_bin).unwrap();
    install_fake_curl(&fake_bin);

    // An archive from before the Pi payload existed: it carries the Codex and
    // Claude payloads only.
    let stale: Vec<&str> = COMPLETE
        .iter()
        .copied()
        .filter(|path| !path.starts_with("pi/"))
        .collect();
    let archive = archive_with(&stale, "v9.9.9", tmp.path());

    // A sentinel stands in for the operator's working install.
    let marketplace = tmp.path().join(".speq-skill");
    fs::create_dir_all(&marketplace).unwrap();
    fs::write(marketplace.join("sentinel"), b"keep me").unwrap();

    let output = run_install_function(
        tmp.path(),
        &fake_bin,
        &format!(
            "export FAKE_ARCHIVE={}; install_from_prebuilt v9.9.9 || echo \"status=$?\"",
            archive.display()
        ),
    );

    let text = stdout(&output);
    assert!(
        text.contains("status=2"),
        "expected status 2 for an incomplete archive, got:\n{text}"
    );
    assert!(
        text.contains("pi/skills") && text.contains("pi/agents"),
        "expected the missing Pi payloads to be named, got:\n{text}"
    );
    assert!(
        marketplace.join("sentinel").exists(),
        "an incomplete archive must not replace the existing install"
    );
}
