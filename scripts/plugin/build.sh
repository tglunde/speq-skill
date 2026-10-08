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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# get_version reads the release version from Cargo.toml (single source of truth).
source "$SCRIPT_DIR/../lib/version.sh"

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

set_codex_skill_model() {
    local file="$1"
    local skill_name="$2"

    case "$skill_name" in
        speq-plan|speq-implement|speq-record|speq-plan-pr|speq-implement-pr|speq-audit)
            sed_in_place 's/^model: sonnet$/model: gpt-5.4/' "$file"
            if ! grep -q '^effort:' "$file"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' '/^model: gpt-5.4$/a\
effort: medium
' "$file"
                else
                    sed -i '/^model: gpt-5.4$/a effort: medium' "$file"
                fi
            fi
            ;;
        *)
            ;;
    esac
}

# --- Pi transforms ---------------------------------------------------------
#
# Pi reads the shared Agent Skills location, so its copies carry the prefixed
# skill name (`speq-<name>`), the `/skill:speq-<name>` invocation, and Pi's own
# tool names. Pi sub-agents live in a directory of their own and carry the same
# `speq-` prefix, so they cannot collide with an operator's own agents.

# Agent names the skills route to. Order does not matter: each pattern refuses a
# match that abuts another name, so `audit-agent` never rewrites the tail of
# `adr-audit-agent`.
PI_AGENT_NAMES=(
    planner-agent
    plan-reviewer
    implementer-agent
    implementer-expert-agent
    code-reviewer
    recorder-agent
    audit-agent
    adr-audit-agent
    architecture-agent
)

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
    # Pi skill frontmatter has no model or effort field.
    sed_in_place '/^model: /d' "$file"
    sed_in_place '/^effort: /d' "$file"
    transform_pi_phrases "$file"
    transform_pi_tool_names "$file"
    prefix_pi_agent_names "$file"
    namespace_pi_skill_invocations "$file"
}

# Pi sub-agent frontmatter drops Claude's `model` and `color`, and carries the
# reasoning level as `thinking`. No model is pinned: Pi model ids are
# provider-specific, so the operator chooses with subagents.agentOverrides.
transform_pi_agent() {
    local file="$1"
    local source_name="$2"
    local target_name="$3"

    sed_in_place "s/^name: $source_name$/name: $target_name/" "$file"
    sed_in_place 's/^effort: /thinking: /' "$file"
    sed_in_place '/^model: /d' "$file"
    sed_in_place '/^color: /d' "$file"
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
                    set_codex_skill_model "$file" "$source_name"
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

set_codex_agent_model() {
    local file="$1"
    local filename="$2"

    case "$filename" in
        planner-agent.md|plan-reviewer.md|implementer-expert-agent.md|code-reviewer.md|audit-agent.md|adr-audit-agent.md|architecture-agent.md)
            sed_in_place 's/^model: .*/model: gpt-5.5/' "$file"
            ;;
        implementer-agent.md|recorder-agent.md)
            sed_in_place 's/^model: .*/model: gpt-5.4/' "$file"
            ;;
        *)
            ;;
    esac
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
                    set_codex_agent_model "$target_file" "$filename"
                fi
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
    version=$(get_version)
    author=$(get_author)

    log_info "Building speq plugin artifacts..."
    log_info "Source: $SOURCE_DIR"
    log_info "Claude target: $CLAUDE_PLUGIN_DIR"
    log_info "Codex target: $CODEX_PLUGIN_DIR"
    log_info "Version: $version (from Cargo.toml)"
    log_info "Author: $author (from Cargo.toml)"
    echo ""

    setup_dirs
    copy_skills
    copy_agents
    generate_manifests "$version" "$author"

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
    log_info "Codex model routing: orchestration gpt-5.4/medium, heavy agents gpt-5.5/xhigh, standard implementation gpt-5.4/high, recording gpt-5.4/medium"
    log_info "Marketplace structure built at: $MARKETPLACE_DIR"
}

main "$@"
