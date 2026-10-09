#!/usr/bin/env bash
set -euo pipefail

# Build speq plugin artifacts from the shared skill source.
# Outputs a Claude marketplace-compatible tree and a Codex plugin tree under
# dist/marketplace/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/.claude"
DIST_DIR="$PROJECT_ROOT/dist"
MARKETPLACE_DIR="$DIST_DIR/marketplace"
CLAUDE_PLUGIN_DIR="$MARKETPLACE_DIR/plugins/speq-skill"
CODEX_PLUGIN_DIR="$MARKETPLACE_DIR/codex/plugins/speq-skill"
CODEX_MARKETPLACE_FILE="$MARKETPLACE_DIR/codex/.agents/plugins/marketplace.json"
# Pi has no plugin manifest: the installer copies this payload into the two
# locations Pi reads, the shared Agent Skills directory and the user agents
# directory.
PI_PLUGIN_DIR="$MARKETPLACE_DIR/pi"
# The routing table is a build input: it never ships in a payload.
ROUTING_TABLE_RELATIVE="model-routing.yml"
ROUTING_TABLE="$PROJECT_ROOT/$ROUTING_TABLE_RELATIVE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# get_version reads the release version from Cargo.toml (single source of truth).
source "$SCRIPT_DIR/../lib/version.sh"
# routing_load, routing_value, routing_names, routing_note, and
# routing_check_coverage read the model routing table.
source "$SCRIPT_DIR/../lib/model-routing.sh"

get_author() {
    grep '^authors' "$PROJECT_ROOT/Cargo.toml" | sed 's/.*\["\([^"]*\)".*/\1/'
}

sed_in_place() {
    local expr="$1"
    local file="$2"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$expr" "$file"
    else
        sed -i "$expr" "$file"
    fi
}

setup_dirs() {
    log_info "Setting up marketplace directory..."
    rm -rf "$MARKETPLACE_DIR"
    mkdir -p "$MARKETPLACE_DIR/.claude-plugin"
    mkdir -p "$MARKETPLACE_DIR/bin"
    mkdir -p "$CLAUDE_PLUGIN_DIR/.claude-plugin"
    mkdir -p "$CLAUDE_PLUGIN_DIR/skills"
    mkdir -p "$CLAUDE_PLUGIN_DIR/agents"
    mkdir -p "$CODEX_PLUGIN_DIR/.codex-plugin"
    mkdir -p "$CODEX_PLUGIN_DIR/skills"
    mkdir -p "$CODEX_PLUGIN_DIR/agents"
    mkdir -p "$(dirname "$CODEX_MARKETPLACE_FILE")"
    mkdir -p "$PI_PLUGIN_DIR/skills"
    mkdir -p "$PI_PLUGIN_DIR/agents"
}

# Rewrite slash-command invocations (`/speq-plan`) to the installed plugin's
# namespaced form (`/speq:plan`), while leaving file-path citations
# (`.claude/skills/speq-plan/references/...`) untouched.
#
# An invocation is terminated by a non-path, non-name character (backtick,
# space, punctuation) or end of line; a path citation continues with `/`.
# The terminator class excludes name characters as well as `/` so the greedy
# name capture cannot backtrack and match a truncated name inside a path.
namespace_slash_commands() {
    local file="$1"

    perl -0pi -e 's{(?<![A-Za-z0-9_./-])/speq-([A-Za-z0-9_-]*)(?=$|[^A-Za-z0-9_/-])}{/speq:$1}g' "$file"
}

# inject_routing_frontmatter <file> <section> <name> <harness>
# Inserts one "<key>: <value>" line after the frontmatter's description line
# for every non-null key of the row's harness map. Claude and Codex carry
# model plus effort; Pi carries thinking only, because a Pi model id belongs
# in the generated settings overrides, not in the emitted frontmatter.
inject_routing_frontmatter() {
    local file="$1"
    local section="$2"
    local name="$3"
    local harness="$4"
    local keys
    local key
    local value
    local insert=""

    case "$harness" in
        pi) keys="thinking" ;;
        *) keys="model effort" ;;
    esac

    for key in $keys; do
        value=$(routing_value "$section" "$name" "$harness" "$key")
        if [[ -n "$value" ]]; then
            insert+="$key: $value"$'\n'
        fi
    done

    if [[ -z "$insert" ]]; then
        return 0
    fi
    if ! grep -q '^description:' "$file"; then
        log_error "Routing injection: $file has no description: frontmatter line"
        exit 1
    fi
    ROUTING_INSERT="$insert" perl -0pi -e 's/^(description:[^\n]*\n)/$1$ENV{ROUTING_INSERT}/m' "$file"
}

transform_common_markdown() {
    local file="$1"
    local source_name="$2"
    local target_name="$3"
    local platform="$4"

    if [[ "$platform" == "codex" ]]; then
        # Codex renders a skill's frontmatter `name:` verbatim in its prompt
        # metadata (no plugin-namespace prefixing), so it must carry the
        # speq: prefix itself. Claude Code applies that namespace on load,
        # so its copy keeps the bare name.
        sed_in_place "s/^name: $source_name$/name: speq:$target_name/" "$file"
    else
        sed_in_place "s/^name: $source_name$/name: $target_name/" "$file"
    fi
    namespace_slash_commands "$file"
}

transform_codex_markdown() {
    local file="$1"

    sed_in_place 's/Claude Code/Codex/g' "$file"
    perl -0pi -e 's{(?<![A-Za-z0-9_./-])/speq:}{\$speq:}g' "$file"
    sed_in_place 's/AskUserQuestion/ask the user/g' "$file"
    sed_in_place 's/AskUserTool/ask the user/g' "$file"
    sed_in_place 's/ExitPlanMode/present the plan and ask the user to proceed/g' "$file"
    sed_in_place 's/TaskCreate/update_plan/g' "$file"
    sed_in_place 's/TaskUpdate/update_plan/g' "$file"
    sed_in_place 's/TaskList/review the current session plan/g' "$file"
    sed_in_place 's/Task(/spawn_agent(/g' "$file"
    sed_in_place 's/subagent_type=/agent_type=/g' "$file"
}

# --- Pi transforms ---------------------------------------------------------
#
# Pi reads the shared Agent Skills location, so its copies carry the prefixed
# skill name (`speq-<name>`), the `/skill:speq-<name>` invocation, and Pi's own
# tool names. Pi sub-agents live in a directory of their own and carry the same
# `speq-` prefix, so they cannot collide with an operator's own agents.

# Agent names the skills route to, derived from the routing table in main().
# Order does not matter: each pattern refuses a match that abuts another name,
# so `audit-agent` never rewrites the tail of `adr-audit-agent`.
PI_AGENT_NAMES=()

# Skills that spawn sub-agents or ask the user questions carry the host note.
PI_HOST_NOTE_SKILLS=(
    speq-plan
    speq-plan-pr
    speq-implement
    speq-implement-pr
    speq-record
    speq-mission
    speq-audit
)

# Sentence-level Pi rewrites. Pi exposes Serena and Context7 tools directly, so
# the Claude "search, then load the schema" instructions are replaced. Each
# pattern is a verbatim sentence from the source: a source edit that rewords one
# leaves the Claude text in the Pi copy, so keep the two in step.
transform_pi_phrases() {
    local file="$1"

    perl -0pi -e '
        s/\QThese tools are deferred in this harness\E.{0,8}\Qa bare tool name has no loaded schema yet.\E/Serena tools are available under the `mcp__serena__` prefix./s;
        s/\QCall `ToolSearch` with the query `serena` to find them, then load the ones you need (`select:<full tool name>`, comma-separated for several) before calling them.\E/Call `searchTools("serena")` in a `codemode` script to list them, then call the ones you need by their `mcp__serena__` names./;
        s/\QFind the tools with `ToolSearch` (query `context7`) and load them before calling.\E/Run `searchTools("context7")` in a `codemode` script to find the tools, then call them./;
        s/\Qwhen the host has no `ToolSearch`, for example Codex\E/when the host has no `searchTools`/;
        s/\Qcall `ToolSearch` with the query `serena`\E/run `searchTools("serena")` in a `codemode` script/;
        s/\Q`ToolSearch` finds no Serena tools\E/`searchTools("serena")` finds no Serena tools/;
        s/\Q`ToolSearch` finds Serena tools\E/`searchTools("serena")` finds Serena tools/;
        s/\Qcarry on with the generic tools (`Read`, `Grep`, `Edit`)\E/carry on with the generic tools (`read`, `grep`, `edit`)/;
        s/^- If Claude Code is in "plan mode", call `ExitPlanMode` and ask to proceed with cleared context$/- Pi has no plan mode. Present the plan and ask the user to proceed with cleared context./m;
    ' "$file"
}

transform_pi_tool_names() {
    local file="$1"

    perl -0pi -e '
        s/\bAskUserQuestion\b/ask_user_question/g;
        s/\bToolSearch\b/searchTools/g;
        s/\bWebSearch\b/web_search/g;
        s/\bExitPlanMode\b/present the plan and ask the user to proceed/g;
        s/\bClaude Code\b/Pi/g;
    ' "$file"
}

prefix_pi_agent_names() {
    local file="$1"
    local agent

    if [[ ${#PI_AGENT_NAMES[@]} -eq 0 ]]; then
        return
    fi
    for agent in "${PI_AGENT_NAMES[@]}"; do
        perl -0pi -e "s{(?<![A-Za-z0-9-])\Q$agent\E(?![A-Za-z0-9-])}{speq-$agent}g" "$file"
    done
}

# `/speq-plan` and the already-namespaced `/speq:plan` -> `/skill:speq-plan`,
# while leaving file-path citations (`.claude/skills/speq-plan/...`) untouched.
namespace_pi_skill_invocations() {
    local file="$1"

    perl -0pi -e 's{(?<![A-Za-z0-9_./-])/speq-([A-Za-z0-9_-]*)(?=$|[^A-Za-z0-9_/-])}{/skill:speq-$1}g; s{(?<![A-Za-z0-9_./-])/speq:([A-Za-z0-9_-]*)(?=$|[^A-Za-z0-9_/-])}{/skill:speq-$1}g' "$file"
}

# Injected once, under the document's H1.
inject_pi_host_note() {
    local file="$1"

    if grep -q '^> \*\*Pi host:\*\*' "$file"; then
        return
    fi

    perl -0pi -e 's{^(# [^\n]*\n)}{$1\n> **Pi host:** spawn every sub-agent this document names with the `subagent` tool: `subagent({ agent: "<name>", task: "<brief>" })`. A `Delegate to <agent> — <title>` line is that call, with the fenced brief below as `task`. Ask the user with `ask_user_question`. Batch independent reads, searches, and git commands into one `codemode` script instead of one tool call each.\n}m' "$file"
}

pi_skill_has_host_note() {
    local skill_name="$1"
    local candidate

    for candidate in "${PI_HOST_NOTE_SKILLS[@]}"; do
        [[ "$skill_name" == "$candidate" ]] && return 0
    done

    return 1
}

transform_pi_markdown() {
    local file="$1"
    local source_name="$2"
    local target_name="$3"

    sed_in_place "s/^name: $source_name$/name: $target_name/" "$file"
    transform_pi_phrases "$file"
    transform_pi_tool_names "$file"
    prefix_pi_agent_names "$file"
    namespace_pi_skill_invocations "$file"
}

# Pi sub-agent frontmatter drops Claude's `color` and carries the reasoning
# level as `thinking` from the routing table. No model is pinned: Pi model ids
# are provider-specific, so the operator chooses with subagents.agentOverrides,
# which the build's pi/model-overrides.json and the installer propagate.
transform_pi_agent() {
    local file="$1"
    local source_name="$2"
    local target_name="$3"

    sed_in_place "s/^name: $source_name$/name: $target_name/" "$file"
    sed_in_place '/^color: /d' "$file"
    inject_routing_frontmatter "$file" agents "$source_name" pi
    transform_pi_phrases "$file"
    transform_pi_tool_names "$file"
    prefix_pi_agent_names "$file"
    namespace_pi_skill_invocations "$file"
}

copy_skill_for_platform() {
    local platform="$1"
    local source_name="$2"
    local target_name="${source_name#speq-}"
    local source_path="$SOURCE_DIR/skills/$source_name"
    local plugin_dir

    case "$platform" in
        claude) plugin_dir="$CLAUDE_PLUGIN_DIR" ;;
        codex) plugin_dir="$CODEX_PLUGIN_DIR" ;;
        pi) plugin_dir="$PI_PLUGIN_DIR"; target_name="$source_name" ;;
        *) log_error "Unknown platform: $platform"; exit 1 ;;
    esac

    local target_path="$plugin_dir/skills/$target_name"

    if [[ -d "$source_path" ]]; then
        log_info "  [$platform] $source_name -> $target_name"
        cp -r "$source_path" "$target_path"

        find "$target_path" -name "*.md" -type f | while read -r file; do
            if [[ "$platform" == "pi" ]]; then
                transform_pi_markdown "$file" "$source_name" "$target_name"
                if [[ "$(basename "$file")" == "SKILL.md" ]] && pi_skill_has_host_note "$source_name"; then
                    inject_pi_host_note "$file"
                fi
            else
                transform_common_markdown "$file" "$source_name" "$target_name" "$platform"
                if [[ "$platform" == "codex" ]]; then
                    transform_codex_markdown "$file"
                fi
                if [[ "$(basename "$file")" == "SKILL.md" ]]; then
                    inject_routing_frontmatter "$file" skills "$source_name" "$platform"
                fi
            fi
        done
    else
        log_warn "  Skill not found: $source_name"
    fi
}

copy_skills() {
    log_info "Copying skills..."

    for skill_dir in "$SOURCE_DIR/skills"/speq-*; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            copy_skill_for_platform claude "$skill_name"
            copy_skill_for_platform codex "$skill_name"
            copy_skill_for_platform pi "$skill_name"
        fi
    done
}

copy_agents_for_platform() {
    local platform="$1"
    local plugin_dir

    case "$platform" in
        claude) plugin_dir="$CLAUDE_PLUGIN_DIR" ;;
        codex) plugin_dir="$CODEX_PLUGIN_DIR" ;;
        pi) plugin_dir="$PI_PLUGIN_DIR" ;;
        *) log_error "Unknown platform: $platform"; exit 1 ;;
    esac

    if [[ ! -d "$SOURCE_DIR/agents" ]]; then
        return
    fi

    for agent_file in "$SOURCE_DIR/agents"/*.md; do
        if [[ -f "$agent_file" ]]; then
            local filename
            local bare_name
            local target_file
            filename=$(basename "$agent_file")
            bare_name="${filename%.md}"
            log_info "  [$platform] $filename"

            if [[ "$platform" == "pi" ]]; then
                target_file="$plugin_dir/agents/speq-$filename"
                cp "$agent_file" "$target_file"
                transform_pi_agent "$target_file" "$bare_name" "speq-$bare_name"
                if [[ "$bare_name" == "planner-agent" ]]; then
                    inject_pi_host_note "$target_file"
                fi
            else
                target_file="$plugin_dir/agents/$filename"
                cp "$agent_file" "$target_file"
                namespace_slash_commands "$target_file"

                if [[ "$platform" == "codex" ]]; then
                    transform_codex_markdown "$target_file"
                fi
                inject_routing_frontmatter "$target_file" agents "$bare_name" "$platform"
            fi
        fi
    done
}

copy_agents() {
    log_info "Copying agents..."
    copy_agents_for_platform claude
    copy_agents_for_platform codex
    copy_agents_for_platform pi
}

generate_agents_json_array() {
    local entries=()
    for agent_file in "$SOURCE_DIR/agents"/*.md; do
        if [[ -f "$agent_file" ]]; then
            entries+=("\"./agents/$(basename "$agent_file")\"")
        fi
    done
    local IFS=,
    echo "[${entries[*]}]"
}

stamp_file() {
    local file="$1"
    local version="$2"
    local author="$3"

    sed_in_place "s/VERSION_PLACEHOLDER/$version/g" "$file"
    sed_in_place "s/AUTHOR_PLACEHOLDER/$author/g" "$file"
}

# validate_frontmatter_line checks if a frontmatter line contains an unquoted
# value with `: ` (colon-space), which breaks YAML parsing.
# Arguments: line, line_number, file_path
# Returns: 0 if valid, 1 if invalid (prints diagnostic)
validate_frontmatter_line() {
    local line="$1"
    local line_num="$2"
    local file="$3"

    # Check if line matches frontmatter key pattern: key: value
    if [[ ! "$line" =~ ^[A-Za-z_-]+:\ .* ]]; then
        return 0  # Not a key-value line, skip
    fi

    # Extract value (everything after "key: ")
    local value="${line#*: }"

    # Strip inline comment: remove trailing " #..." (space-hash-anything)
    # This handles "value # comment" but not "# inside value"
    value=$(printf '%s' "$value" | sed 's/[[:space:]]#.*$//')

    # If value starts with " or ', it's quoted - OK
    if [[ "$value" =~ ^[\"\'] ]]; then
        return 0
    fi

    # Check if value contains ": " (colon-space)
    if [[ "$value" == *": "* ]]; then
        log_error "Frontmatter guard: $file:$line_num unquoted value contains ': '"
        log_error "  Value: $value"
        return 1
    fi

    return 0
}

# guard_frontmatter scans all .md files under the given directory for frontmatter
# values that contain unquoted `: ` sequences.
# Arguments: directory (defaults to $MARKETPLACE_DIR)
# Returns: 0 if all files pass, 1 if any file fails
guard_frontmatter() {
    local dir="${1:-$MARKETPLACE_DIR}"
    local failed=0

    if [[ ! -d "$dir" ]]; then
        log_error "Frontmatter guard: directory does not exist: $dir"
        return 1
    fi

    while IFS= read -r -d '' file; do
        local in_frontmatter=0
        local line_num=0
        local frontmatter_start_found=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            line_num=$((line_num + 1))

            # Track frontmatter boundaries
            if [[ "$line" == "---" ]]; then
                if [[ $frontmatter_start_found -eq 0 ]]; then
                    frontmatter_start_found=1
                    in_frontmatter=1
                    continue
                elif [[ $in_frontmatter -eq 1 ]]; then
                    # End of frontmatter
                    break
                fi
            fi

            if [[ $in_frontmatter -eq 1 ]]; then
                if ! validate_frontmatter_line "$line" "$line_num" "$file"; then
                    failed=1
                fi
            fi
        done < "$file"
    done < <(find "$dir" -name "*.md" -type f -print0)

    return $failed
}

# run_guard_self_test creates a temporary fixture with a known-bad frontmatter
# value, verifies the guard catches it, then removes the fixture.
# Returns: 0 if self-test passes (guard correctly caught the defect), 1 otherwise
run_guard_self_test() {
    local test_dir
    test_dir=$(mktemp -d)
    local fixture="$test_dir/_guard_test.md"
    local result=0

    # Create fixture with known-bad frontmatter
    cat > "$fixture" << 'EOF'
---
name: test-fixture
description: bad: value
---
# Test
EOF

    log_info "Running frontmatter guard self-test..."

    # Guard should return non-zero for this fixture
    # Redirect stderr to /dev/null since we expect an error message
    if guard_frontmatter "$test_dir" >/dev/null 2>&1; then
        log_error "Frontmatter guard self-test FAILED: guard did not catch bad fixture"
        result=1
    else
        log_info "Frontmatter guard self-test passed"
    fi

    # Always clean up the test directory
    rm -rf "$test_dir"

    return $result
}

# run_routing_self_test writes one fixture per malformed table shape into a
# temporary directory, verifies routing_load rejects each of them, verifies a
# well-formed fixture is accepted, then removes the fixtures. It mirrors
# run_guard_self_test: a validator that silently accepts bad input is worse
# than no validator, because it lets the drift return unnoticed.
# Returns: 0 if the self-test passes, 1 otherwise
run_routing_self_test() {
    local test_dir
    local result=0
    local fixture

    test_dir=$(mktemp -d)
    log_info "Running routing table validator self-test..."

    printf 'agents:\n\tplanner-agent:\n' > "$test_dir/tab.yml"

    cat > "$test_dir/unknown-section.yml" <<'EOF'
services:
  planner-agent:
EOF

    cat > "$test_dir/unknown-flow-key.yml" <<'EOF'
agents:
  planner-agent:
    file: .claude/agents/planner-agent.md
    note: fixture
    claude: { model: opus, temperature: high }
    codex: {}
    pi: {}
skills:
EOF

    cat > "$test_dir/quoted-value.yml" <<'EOF'
agents:
  planner-agent:
    file: .claude/agents/planner-agent.md
    note: fixture
    claude: { model: "opus" }
    codex: {}
    pi: {}
skills:
EOF

    cat > "$test_dir/row-without-file.yml" <<'EOF'
agents:
  planner-agent:
    note: fixture
    claude: {}
    codex: {}
    pi: {}
skills:
EOF

    cat > "$test_dir/valid.yml" <<'EOF'
agents:
  planner-agent:
    file: .claude/agents/planner-agent.md
    note: fixture
    claude: { model: opus, effort: xhigh }
    codex: { model: gpt-5.5, effort: xhigh }
    pi: { model: null, thinking: xhigh }
skills:
  speq-plan:
    file: .claude/skills/speq-plan/SKILL.md
    note: fixture
    claude: { model: sonnet }
    codex: { model: gpt-5.4, effort: medium }
    pi: {}
EOF

    for fixture in tab unknown-section unknown-flow-key quoted-value row-without-file; do
        if routing_load "$test_dir/$fixture.yml" >/dev/null 2>&1; then
            log_error "Routing validator self-test FAILED: $fixture.yml was accepted"
            result=1
        fi
    done

    if ! routing_load "$test_dir/valid.yml" >/dev/null 2>&1; then
        log_error "Routing validator self-test FAILED: a valid table was rejected"
        result=1
    fi

    if [[ $result -eq 0 ]]; then
        log_info "Routing validator self-test passed (5 malformed fixtures rejected, 1 valid accepted)"
    fi

    rm -rf "$test_dir"
    return $result
}

# guard_source_frontmatter fails when a source agent or skill still carries a
# routing value. Routing lives in the table alone, so a re-added line is the
# drift the build must stop before it writes an artifact.
# Returns: 0 if every source frontmatter is clean, 1 otherwise
guard_source_frontmatter() {
    local failed=0
    local file
    local line
    local line_num
    local in_frontmatter

    for file in "$SOURCE_DIR/agents"/*.md "$SOURCE_DIR/skills"/speq-*/SKILL.md; do
        [[ -f "$file" ]] || continue
        in_frontmatter=0
        line_num=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            line_num=$((line_num + 1))
            if [[ "$line" == "---" ]]; then
                if [[ $in_frontmatter -eq 0 ]]; then
                    in_frontmatter=1
                    continue
                fi
                break
            fi
            if [[ $in_frontmatter -eq 1 && "$line" =~ ^(model|effort|thinking): ]]; then
                log_error "Source routing guard: $file:$line_num carries a routing value"
                log_error "  $line"
                log_error "  Move it to $ROUTING_TABLE_RELATIVE"
                failed=1
            fi
        done < "$file"
    done

    return $failed
}

# generate_pi_model_overrides writes the Pi payload's model-overrides.json
# from the table's non-null pi.model values, in table order. The installer
# reads this artifact and never parses the table.
generate_pi_model_overrides() {
    local json="{"
    local first=1
    local name
    local model

    while IFS= read -r name; do
        model=$(routing_value agents "$name" pi model)
        if [[ -n "$model" ]]; then
            if [[ $first -eq 1 ]]; then
                first=0
            else
                json+=", "
            fi
            json+="\"speq-$name\": \"$model\""
        fi
    done < <(routing_names agents)
    json+="}"

    printf '%s\n' "$json" > "$PI_PLUGIN_DIR/model-overrides.json"
    log_info "Pi model overrides: $json"
}

# assert_no_routing_table_in_payload fails when any payload directory
# contains the routing table, which is a build input and never a payload file.
assert_no_routing_table_in_payload() {
    local matches

    matches=$(find "$MARKETPLACE_DIR" -name "$(basename "$ROUTING_TABLE")" -type f)
    if [[ -n "$matches" ]]; then
        log_error "Routing table leaked into the payload: $matches"
        return 1
    fi
    return 0
}

generate_manifests() {
    local version="$1"
    local author="$2"

    log_info "Generating manifests (version=$version, author=$author)..."

    cp "$SCRIPT_DIR/plugin.json" "$CLAUDE_PLUGIN_DIR/.claude-plugin/plugin.json"
    stamp_file "$CLAUDE_PLUGIN_DIR/.claude-plugin/plugin.json" "$version" "$author"
    sed_in_place "s|AGENTS_PLACEHOLDER|$(generate_agents_json_array)|" \
        "$CLAUDE_PLUGIN_DIR/.claude-plugin/plugin.json"

    cp "$SCRIPT_DIR/marketplace.json" "$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
    stamp_file "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" "$version" "$author"

    cp "$SCRIPT_DIR/codex-plugin.json" "$CODEX_PLUGIN_DIR/.codex-plugin/plugin.json"
    stamp_file "$CODEX_PLUGIN_DIR/.codex-plugin/plugin.json" "$version" "$author"

    cp "$SCRIPT_DIR/codex-marketplace.json" "$CODEX_MARKETPLACE_FILE"
    stamp_file "$CODEX_MARKETPLACE_FILE" "$version" "$author"
}

main() {
    local version
    local author
    local agent_name
    version=$(get_version)
    author=$(get_author)

    log_info "Building speq plugin artifacts..."
    log_info "Source: $SOURCE_DIR"
    log_info "Claude target: $CLAUDE_PLUGIN_DIR"
    log_info "Codex target: $CODEX_PLUGIN_DIR"
    log_info "Version: $version (from Cargo.toml)"
    log_info "Author: $author (from Cargo.toml)"
    echo ""

    # Validate every input before setup_dirs, so no failure path writes an
    # artifact. A table or source defect stops the build instead of emitting a
    # half-routed payload.
    if ! run_routing_self_test; then
        exit 1
    fi
    if ! routing_load "$ROUTING_TABLE"; then
        log_error "Routing table validation failed: $ROUTING_TABLE_RELATIVE"
        exit 1
    fi
    if ! routing_check_coverage "$SOURCE_DIR"; then
        log_error "Routing table coverage check failed"
        exit 1
    fi
    log_info "Routing table valid: $(routing_names agents | wc -l | tr -d ' ') agents, $(routing_names skills | wc -l | tr -d ' ') skills"
    if ! guard_source_frontmatter; then
        log_error "Source frontmatter guard failed: routing values live in $ROUTING_TABLE_RELATIVE"
        exit 1
    fi
    log_info "Source frontmatter guard passed (no routing values in .claude/)"

    # PI_AGENT_NAMES drives the Pi agent-name prefixing; it comes from the
    # table so there is no second hardcoded list to drift.
    PI_AGENT_NAMES=()
    while IFS= read -r agent_name; do
        PI_AGENT_NAMES+=("$agent_name")
    done < <(routing_names agents)

    setup_dirs
    copy_skills
    copy_agents
    generate_manifests "$version" "$author"
    generate_pi_model_overrides
    assert_no_routing_table_in_payload

    # Run self-test, then guard real content
    if ! run_guard_self_test; then
        exit 1
    fi

    log_info "Running frontmatter guard on marketplace artifacts..."
    if ! guard_frontmatter "$MARKETPLACE_DIR"; then
        log_error "Frontmatter guard failed: fix the above errors before publishing"
        exit 1
    fi
    log_info "Frontmatter guard passed (all files clean)"

    echo ""
    log_info "Plugin artifacts built successfully!"
    log_info "Structure:"
    find "$MARKETPLACE_DIR" -type f | sed "s|$MARKETPLACE_DIR/||" | sort | while read -r f; do
        echo "  $f"
    done

    echo ""
    log_info "Claude test: claude --plugin-dir $CLAUDE_PLUGIN_DIR"
    log_info "Codex plugin: $CODEX_PLUGIN_DIR"
    log_info "Workflow skills: /speq:plan, /speq:implement, /speq:record, /speq:mission, /speq:audit"
    log_info "Headless PR pipeline: /speq:plan-pr, /speq:implement-pr"
    log_info "Utility skills: /speq:code-tools, /speq:ext-research, /speq:code-guardrails, /speq:design-philosophy, /speq:git-discipline, /speq:cli, /speq:writing-guardrails, /speq:planning, /speq:plan-review, /speq:code-review, /speq:spec-merge, /speq:git-operations, /speq:adr-rules"
    log_info "Model routing: $ROUTING_TABLE_RELATIVE"
    log_info "Marketplace structure built at: $MARKETPLACE_DIR"
}

main "$@"
