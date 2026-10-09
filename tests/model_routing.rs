//! Integration tests for the model routing table, the plugin build, and the
//! documentation renderer.
//!
//! Every test builds from a temporary copy of `.claude/`, `scripts/`,
//! `model-routing.yml`, and `Cargo.toml`, so `cargo test` never writes the
//! repository's `dist/`. The
//! malformed-table and source fixtures live under `tests/fixtures/model_routing/`.
//! Where available, `/bin/bash` is used to keep the bash 3.2 path exercised.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::OnceLock;

use tempfile::TempDir;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn fixtures() -> PathBuf {
    repo_root().join("tests/fixtures/model_routing")
}

/// Prefer the system bash (3.2 on macOS) so the build stays bash 3.2 clean.
fn bash() -> &'static str {
    if Path::new("/bin/bash").exists() {
        "/bin/bash"
    } else {
        "bash"
    }
}

fn copy_dir_recursive(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).unwrap_or_else(|e| panic!("create {}: {e}", dst.display()));
    for entry in fs::read_dir(src).unwrap_or_else(|e| panic!("read {}: {e}", src.display())) {
        let entry = entry.unwrap();
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path);
        } else {
            fs::copy(&src_path, &dst_path)
                .unwrap_or_else(|e| panic!("copy {}: {e}", src_path.display()));
        }
    }
}

/// Copy the plugin build inputs into a fresh temporary project root.
fn setup_project() -> TempDir {
    let tmp = TempDir::new().unwrap();
    let root = tmp.path();
    copy_dir_recursive(&repo_root().join(".claude"), &root.join(".claude"));
    copy_dir_recursive(&repo_root().join("scripts"), &root.join("scripts"));
    fs::copy(
        repo_root().join("model-routing.yml"),
        root.join("model-routing.yml"),
    )
    .unwrap();
    fs::copy(repo_root().join("Cargo.toml"), root.join("Cargo.toml")).unwrap();
    tmp
}

fn run_build(root: &Path) -> Output {
    Command::new(bash())
        .arg(root.join("scripts/plugin/build.sh"))
        .current_dir(root)
        .output()
        .expect("run build.sh")
}

fn combined(output: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}

fn assert_build_succeeded(output: &Output, context: &str) {
    assert!(
        output.status.success(),
        "{context}: build.sh failed\n{}",
        combined(output)
    );
}

fn assert_build_failed(output: &Output, context: &str) -> String {
    assert!(
        !output.status.success(),
        "{context}: build.sh unexpectedly succeeded\n{}",
        combined(output)
    );
    combined(output)
}

fn install_fixture_table(root: &Path, fixture: &str) {
    fs::copy(
        fixtures().join("tables").join(fixture),
        root.join("model-routing.yml"),
    )
    .unwrap_or_else(|e| panic!("install fixture table {fixture}: {e}"));
}

/// One successful build shared by the read-only assertions, so the suite pays
/// for the full plugin build once.
fn shared_build() -> &'static Path {
    static SHARED: OnceLock<(TempDir, PathBuf)> = OnceLock::new();
    let (_, root) = SHARED.get_or_init(|| {
        let tmp = setup_project();
        let output = run_build(tmp.path());
        assert_build_succeeded(&output, "shared build");
        let root = tmp.path().to_path_buf();
        (tmp, root)
    });
    root
}

fn frontmatter(path: &Path) -> String {
    let content =
        fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let mut lines = content.lines();
    assert_eq!(
        lines.next(),
        Some("---"),
        "{}: expected YAML frontmatter",
        path.display()
    );
    let mut frontmatter = String::new();
    for line in lines {
        if line == "---" {
            return frontmatter;
        }
        frontmatter.push_str(line);
        frontmatter.push('\n');
    }
    panic!("{}: unterminated frontmatter", path.display());
}

fn assert_has_line(frontmatter: &str, line: &str, context: &str) {
    assert!(
        frontmatter.lines().any(|candidate| candidate == line),
        "{context}: expected frontmatter line {line:?}\n{frontmatter}"
    );
}

fn assert_lacks_prefix(frontmatter: &str, prefix: &str, context: &str) {
    let offending: Vec<&str> = frontmatter
        .lines()
        .filter(|line| line.starts_with(prefix))
        .collect();
    assert!(
        offending.is_empty(),
        "{context}: unexpected frontmatter {offending:?}\n{frontmatter}"
    );
}

fn claude_agent(root: &Path, name: &str) -> PathBuf {
    root.join(format!(
        "dist/marketplace/plugins/speq-skill/agents/{name}.md"
    ))
}

fn codex_agent(root: &Path, name: &str) -> PathBuf {
    root.join(format!(
        "dist/marketplace/codex/plugins/speq-skill/agents/{name}.md"
    ))
}

fn pi_agent(root: &Path, name: &str) -> PathBuf {
    root.join(format!("dist/marketplace/pi/agents/speq-{name}.md"))
}

/// The Claude and Codex plugin skill directories drop the `speq-` prefix.
fn claude_skill(root: &Path, bare_name: &str) -> PathBuf {
    root.join(format!(
        "dist/marketplace/plugins/speq-skill/skills/{bare_name}/SKILL.md"
    ))
}

fn codex_skill(root: &Path, bare_name: &str) -> PathBuf {
    root.join(format!(
        "dist/marketplace/codex/plugins/speq-skill/skills/{bare_name}/SKILL.md"
    ))
}

/// The Pi payload keeps the `speq-` prefix.
fn pi_skill(root: &Path, name: &str) -> PathBuf {
    root.join(format!("dist/marketplace/pi/skills/{name}/SKILL.md"))
}

fn assert_no_routing_table_in_payload(root: &Path) {
    let marketplace = root.join("dist/marketplace");
    let mut stack = vec![marketplace];
    while let Some(dir) = stack.pop() {
        for entry in fs::read_dir(&dir).unwrap_or_else(|e| panic!("read {}: {e}", dir.display())) {
            let path = entry.unwrap().path();
            if path.is_dir() {
                stack.push(path);
            } else {
                assert_ne!(
                    path.file_name().and_then(|name| name.to_str()),
                    Some("model-routing.yml"),
                    "the routing table is a build input and must not ship in a payload"
                );
            }
        }
    }
}

#[test]
fn build_injects_claude_routing() {
    let root = shared_build();

    let agent = frontmatter(&claude_agent(root, "planner-agent"));
    assert_has_line(&agent, "model: opus", "claude planner-agent");
    assert_has_line(&agent, "effort: xhigh", "claude planner-agent");
    assert_has_line(&agent, "color: blue", "claude planner-agent keeps color");

    let skill = frontmatter(&claude_skill(root, "plan"));
    assert_has_line(&skill, "model: sonnet", "claude plan skill");
    assert_lacks_prefix(&skill, "effort:", "claude plan skill");
}

#[test]
fn build_injects_codex_routing() {
    let root = shared_build();

    let agent = frontmatter(&codex_agent(root, "planner-agent"));
    assert_has_line(&agent, "model: gpt-5.5", "codex planner-agent");
    assert_has_line(&agent, "effort: xhigh", "codex planner-agent");
    assert_has_line(&agent, "color: blue", "codex planner-agent keeps color");

    let skill = frontmatter(&codex_skill(root, "plan"));
    assert_has_line(&skill, "model: gpt-5.4", "codex plan skill");
    assert_has_line(&skill, "effort: medium", "codex plan skill");
}

#[test]
fn build_emits_pi_thinking_only() {
    let root = shared_build();

    let agent = frontmatter(&pi_agent(root, "planner-agent"));
    assert_has_line(&agent, "thinking: xhigh", "pi planner-agent");
    assert_lacks_prefix(&agent, "model:", "pi planner-agent");
    assert_lacks_prefix(&agent, "effort:", "pi planner-agent");
    assert_lacks_prefix(&agent, "color:", "pi planner-agent");

    let skill = frontmatter(&pi_skill(root, "speq-plan"));
    assert_lacks_prefix(&skill, "model:", "pi plan skill");
    assert_lacks_prefix(&skill, "effort:", "pi plan skill");
    assert_lacks_prefix(&skill, "thinking:", "pi plan skill");
}

#[test]
fn build_inherits_on_empty_harness_map() {
    let root = shared_build();

    let claude = frontmatter(&claude_skill(root, "cli"));
    assert_lacks_prefix(&claude, "model:", "claude cli skill");
    assert_lacks_prefix(&claude, "effort:", "claude cli skill");

    let codex = frontmatter(&codex_skill(root, "cli"));
    assert_lacks_prefix(&codex, "model:", "codex cli skill");
    assert_lacks_prefix(&codex, "effort:", "codex cli skill");

    let pi = frontmatter(&pi_skill(root, "speq-cli"));
    assert_lacks_prefix(&pi, "model:", "pi cli skill");
    assert_lacks_prefix(&pi, "effort:", "pi cli skill");
    assert_lacks_prefix(&pi, "thinking:", "pi cli skill");
}

#[test]
fn build_does_not_inherit_values_from_a_previous_load() {
    // build.sh calls routing_load for every self-test fixture and then for the
    // real table. The validator self-test's valid fixture pins planner-agent to
    // `model: opus, effort: xhigh`, so a load that only overwrites the fields
    // the new table sets would leak those values into the emitted payload when
    // the real row carries an empty map.
    let tmp = setup_project();
    let table_path = tmp.path().join("model-routing.yml");
    let table = fs::read_to_string(&table_path).unwrap();
    let stripped = table.replacen("claude: { model: opus, effort: xhigh }", "claude: {}", 1);
    assert_ne!(
        table, stripped,
        "the shipped table must still carry the planner-agent claude map to mutate"
    );
    fs::write(&table_path, &stripped).unwrap();

    let output = run_build(tmp.path());
    assert_build_succeeded(&output, "build with an empty planner-agent claude map");

    let agent = frontmatter(&claude_agent(tmp.path(), "planner-agent"));
    assert_lacks_prefix(&agent, "model:", "claude planner-agent after empty map");
    assert_lacks_prefix(&agent, "effort:", "claude planner-agent after empty map");
}

#[test]
fn build_rejects_out_of_subset_line() {
    let tmp = setup_project();
    let cases = [
        ("tab-line.yml", "tab characters are not allowed"),
        ("unknown-section.yml", "unknown section header"),
        ("unknown-flow-key.yml", "unknown flow-map key"),
        (
            "quoted-value.yml",
            "quoted flow-map values are not supported",
        ),
        ("missing-file-property.yml", "has no file: property"),
        ("missing-note-property.yml", "has no note: property"),
        ("missing-harness-map.yml", "has no pi: map"),
    ];

    for (fixture, expected) in cases {
        install_fixture_table(tmp.path(), fixture);
        let output = run_build(tmp.path());
        let text = assert_build_failed(&output, fixture);
        assert!(
            text.contains(expected),
            "{fixture}: expected {expected:?} in build output\n{text}"
        );
        assert!(
            text.contains("model-routing.yml:"),
            "{fixture}: the error must name the file and line\n{text}"
        );
        assert!(
            !tmp.path().join("dist").exists(),
            "{fixture}: a failed build must not write an artifact"
        );
    }
}

#[test]
fn build_rejects_missing_routing_row() {
    let tmp = setup_project();
    install_fixture_table(tmp.path(), "missing-row.yml");

    let output = run_build(tmp.path());
    let text = assert_build_failed(&output, "missing row");
    assert!(text.contains("no routing row"), "{text}");
    assert!(text.contains(".claude/agents/planner-agent.md"), "{text}");
    assert!(
        !tmp.path().join("dist").exists(),
        "a failed build must not write an artifact"
    );
}

#[test]
fn build_rejects_row_without_file() {
    let tmp = setup_project();
    install_fixture_table(tmp.path(), "ghost-row.yml");

    let output = run_build(tmp.path());
    let text = assert_build_failed(&output, "ghost row");
    assert!(text.contains("ghost-agent"), "{text}");
    assert!(text.contains(".claude/agents/ghost-agent.md"), "{text}");
    assert!(
        !tmp.path().join("dist").exists(),
        "a failed build must not write an artifact"
    );
}

#[test]
fn build_rejects_source_frontmatter_routing() {
    let tmp = setup_project();
    fs::copy(
        fixtures().join("sources/agent-with-routing-frontmatter.md"),
        tmp.path().join(".claude/agents/planner-agent.md"),
    )
    .unwrap();
    fs::copy(
        fixtures().join("sources/skill-with-routing-frontmatter.md"),
        tmp.path().join(".claude/skills/speq-plan/SKILL.md"),
    )
    .unwrap();

    let output = run_build(tmp.path());
    let text = assert_build_failed(&output, "source frontmatter");
    assert!(text.contains("planner-agent.md:"), "{text}");
    assert!(text.contains("model: opus"), "{text}");
    assert!(text.contains("effort: xhigh"), "{text}");
    assert!(text.contains("thinking: xhigh"), "{text}");
    assert!(
        text.contains(".claude/skills/speq-plan/SKILL.md:"),
        "{text}"
    );
    assert!(text.contains("model: sonnet"), "{text}");
    assert!(
        !tmp.path().join("dist").exists(),
        "a failed build must not write an artifact"
    );
}

/// The `speq-<name>` to model mapping `model-routing.yml` declares, read
/// through the same lookup helpers the build uses. Deriving the expectation
/// keeps the table the only place a routing value lives: this file names
/// agents and structural shapes, never a model id.
fn table_pi_model_pins(root: &Path) -> Vec<(String, String)> {
    let output = Command::new(bash())
        .args([
            "-c",
            r#"
source scripts/lib/model-routing.sh
routing_load model-routing.yml
for name in $(routing_names agents); do
    model=$(routing_value agents "$name" pi model)
    [ -n "$model" ] || continue
    printf 'speq-%s\t%s\n' "$name" "$model"
done
"#,
        ])
        .current_dir(root)
        .output()
        .expect("read the routing table");
    assert_build_succeeded(&output, "routing table lookup");

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| {
            let (name, model) = line
                .split_once('\t')
                .unwrap_or_else(|| panic!("expected 'name<TAB>model', got {line:?}"));
            (name.to_string(), model.to_string())
        })
        .collect()
}

/// The artifact text the table's pins imply, in table order.
fn expected_pi_model_overrides(root: &Path) -> String {
    let body = table_pi_model_pins(root)
        .iter()
        .map(|(name, model)| format!("\"{name}\": \"{model}\""))
        .collect::<Vec<_>>()
        .join(", ");
    format!("{{{body}}}")
}

/// Replace one agent's `pi.model` in the table text. The caller names the row
/// and the replacement, so a shipped value is never restated here.
fn set_pi_model(table: &str, agent: &str, model: &str) -> String {
    let row = format!("\n  {agent}:\n");
    let row_start = table
        .find(&row)
        .unwrap_or_else(|| panic!("the table has no row '{agent}'"))
        + row.len();
    let line_start = row_start
        + table[row_start..]
            .find("    pi: { model: ")
            .unwrap_or_else(|| panic!("row '{agent}' has no pi.model"));
    let line_end = line_start + table[line_start..].find('\n').expect("the line ends");
    let tail = table[line_start..line_end]
        .find(", thinking: ")
        .expect("the pi map carries thinking after model");
    let replaced = format!(
        "    pi: {{ model: {model}{}",
        &table[line_start + tail..line_end]
    );
    format!("{}{replaced}{}", &table[..line_start], &table[line_end..])
}

#[test]
fn build_writes_pi_model_overrides_artifact() {
    let root = shared_build();
    let artifact = root.join("dist/marketplace/pi/model-overrides.json");
    let shipped = fs::read_to_string(&artifact).unwrap();

    let pins = table_pi_model_pins(&repo_root());
    assert!(
        !pins.is_empty(),
        "the shipped table must declare a Pi pin for this test to mean anything"
    );
    assert_eq!(
        shipped.trim(),
        expected_pi_model_overrides(&repo_root()),
        "the artifact must agree with the pins model-routing.yml declares"
    );

    // Repin one row and clear another in a temporary copy of the table.
    let tmp = setup_project();
    let table_path = tmp.path().join("model-routing.yml");
    let table = fs::read_to_string(&table_path).unwrap();
    let repinned = set_pi_model(&table, "planner-agent", "test-model-a");
    assert_ne!(table, repinned, "the repin must change the table");
    let pinned = set_pi_model(&repinned, "plan-reviewer", "null");
    assert_ne!(repinned, pinned, "the clear must change the table");
    fs::write(&table_path, &pinned).unwrap();

    let output = run_build(tmp.path());
    assert_build_succeeded(&output, "pinned build");

    let artifact = tmp.path().join("dist/marketplace/pi/model-overrides.json");
    let content = fs::read_to_string(&artifact).unwrap();
    assert!(
        content.contains(r#""speq-planner-agent": "test-model-a""#),
        "a repinned row must reach the mapping: {content}"
    );
    assert!(
        !content.contains("plan-reviewer"),
        "rows with a null pi.model must be absent from the mapping: {content}"
    );

    // A pinned Pi model still never reaches the emitted frontmatter.
    let agent = frontmatter(&pi_agent(tmp.path(), "planner-agent"));
    assert_lacks_prefix(&agent, "model:", "pinned pi planner-agent");

    assert_no_routing_table_in_payload(root);
    assert_no_routing_table_in_payload(tmp.path());
}

#[test]
fn docs_match_routing_table() {
    let tmp = setup_project();
    copy_dir_recursive(&repo_root().join("docs"), &tmp.path().join("docs"));
    let target = tmp.path().join("docs/model-routing.md");

    let committed = fs::read_to_string(repo_root().join("docs/model-routing.md")).unwrap();
    for marker in [
        "<!-- BEGIN GENERATED claude routing table -->",
        "<!-- END GENERATED claude routing table -->",
        "<!-- BEGIN GENERATED codex routing table -->",
        "<!-- END GENERATED codex routing table -->",
        "<!-- BEGIN GENERATED pi routing table -->",
        "<!-- END GENERATED pi routing table -->",
    ] {
        assert!(
            committed.contains(marker),
            "the committed document is missing the marker {marker:?}"
        );
    }

    let output = Command::new(bash())
        .arg(
            tmp.path()
                .join("scripts/plugin/render-model-routing-docs.sh"),
        )
        .current_dir(tmp.path())
        .output()
        .expect("run render-model-routing-docs.sh");
    assert_build_succeeded(&output, "docs render");

    let rendered = fs::read_to_string(&target).unwrap();
    assert_eq!(
        rendered, committed,
        "docs/model-routing.md is stale; run ./scripts/plugin/render-model-routing-docs.sh"
    );

    // A stale table block is rewritten, not preserved.
    let stale = rendered.replacen(
        "| `/speq:plan` | `sonnet` |",
        "| `/speq:plan` | `stale-model` |",
        1,
    );
    assert_ne!(
        stale, rendered,
        "the committed doc must carry the expected row"
    );
    fs::write(&target, &stale).unwrap();

    let output = Command::new(bash())
        .arg(
            tmp.path()
                .join("scripts/plugin/render-model-routing-docs.sh"),
        )
        .current_dir(tmp.path())
        .output()
        .expect("re-run render-model-routing-docs.sh");
    assert_build_succeeded(&output, "docs re-render");
    assert_eq!(
        fs::read_to_string(&target).unwrap(),
        committed,
        "the renderer must overwrite a stale table block"
    );
}
