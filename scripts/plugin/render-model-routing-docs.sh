#!/usr/bin/env bash
set -euo pipefail

# Render the three harness routing tables from model-routing.yml at the
# repository root into marked blocks of a target document, default
# docs/model-routing.md.
#
# The plugin build must not rewrite a tracked file, so this renderer is a
# separate, explicit step. The docs check in tests/model_routing.rs fails when
# the committed document is stale, so a missed run is a test failure rather
# than silent drift.
#
# Usage: render-model-routing-docs.sh [target-path]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROUTING_TABLE="$PROJECT_ROOT/model-routing.yml"
TARGET="${1:-$PROJECT_ROOT/docs/model-routing.md}"

source "$SCRIPT_DIR/../lib/model-routing.sh"

# The EXIT trap runs after main returns, so the temp directory cannot be a
# local of main.
TMPDIR_WORK=""
cleanup() {
    if [[ -n "$TMPDIR_WORK" ]]; then
        rm -rf "$TMPDIR_WORK"
    fi
}
trap cleanup EXIT

# cell <value> renders one routing value; a missing or null value means the
# harness inherits its default.
cell() {
    if [[ -n "$1" ]]; then
        printf '`%s`' "$1"
    else
        printf 'inherited'
    fi
}

render_row() {
    printf '| `%s` | %s | %s | %s |\n' "$1" "$2" "$3" "$4"
}

render_claude_table() {
    local name

    printf '| Skill or agent | Model | Effort | Notes |\n'
    printf '|----------------|-------|--------|-------|\n'
    while IFS= read -r name; do
        render_row "/speq:${name#speq-}" \
            "$(cell "$(routing_value skills "$name" claude model)")" \
            "$(cell "$(routing_value skills "$name" claude effort)")" \
            "$(routing_note skills "$name")"
    done < <(routing_names skills)
    while IFS= read -r name; do
        render_row "$name" \
            "$(cell "$(routing_value agents "$name" claude model)")" \
            "$(cell "$(routing_value agents "$name" claude effort)")" \
            "$(routing_note agents "$name")"
    done < <(routing_names agents)
}

render_codex_table() {
    local name

    printf '| Skill or agent | Model | Effort | Notes |\n'
    printf '|----------------|-------|--------|-------|\n'
    while IFS= read -r name; do
        render_row "/speq:${name#speq-}" \
            "$(cell "$(routing_value skills "$name" codex model)")" \
            "$(cell "$(routing_value skills "$name" codex effort)")" \
            "$(routing_note skills "$name")"
    done < <(routing_names skills)
    while IFS= read -r name; do
        render_row "$name" \
            "$(cell "$(routing_value agents "$name" codex model)")" \
            "$(cell "$(routing_value agents "$name" codex effort)")" \
            "$(routing_note agents "$name")"
    done < <(routing_names agents)
}

render_pi_table() {
    local name

    printf '| Skill or agent | Model | Thinking | Notes |\n'
    printf '|----------------|-------|----------|-------|\n'
    while IFS= read -r name; do
        render_row "/skill:$name" \
            "$(cell "$(routing_value skills "$name" pi model)")" \
            "$(cell "$(routing_value skills "$name" pi thinking)")" \
            "$(routing_note skills "$name")"
    done < <(routing_names skills)
    while IFS= read -r name; do
        render_row "speq-$name" \
            "$(cell "$(routing_value agents "$name" pi model)")" \
            "$(cell "$(routing_value agents "$name" pi thinking)")" \
            "$(routing_note agents "$name")"
    done < <(routing_names agents)
}

# replace_marked_block <source> <dest> <begin> <end> <block>
# Copies source to dest, replacing every line between the begin and end marker
# lines with the contents of block. Both marker lines survive. Returns 3 when
# either marker line is absent, so a near-miss marker cannot silently skip the
# replacement.
replace_marked_block() {
    local source="$1"
    local dest="$2"
    local begin="$3"
    local end="$4"
    local block="$5"

    awk -v begin="$begin" -v end="$end" -v block="$block" '
        $0 == begin {
            print
            while ((getline line < block) > 0) print line
            close(block)
            found = 1
            skipping = 1
            next
        }
        $0 == end { skipping = 0; closed = 1 }
        !skipping { print }
        END { if (!found || !closed) exit 3 }
    ' "$source" > "$dest"
}

main() {
    local harness
    local begin
    local end
    local block
    local out
    local work

    if [[ ! -f "$TARGET" ]]; then
        printf 'render-model-routing-docs: no such target: %s\n' "$TARGET" >&2
        exit 1
    fi
    if ! routing_load "$ROUTING_TABLE"; then
        printf 'render-model-routing-docs: routing table is invalid: %s\n' "$ROUTING_TABLE" >&2
        exit 1
    fi

    TMPDIR_WORK=$(mktemp -d)

    for harness in claude codex pi; do
        case "$harness" in
            claude) render_claude_table > "$TMPDIR_WORK/$harness.md" ;;
            codex) render_codex_table > "$TMPDIR_WORK/$harness.md" ;;
            pi) render_pi_table > "$TMPDIR_WORK/$harness.md" ;;
        esac
    done

    work="$TARGET"
    for harness in claude codex pi; do
        begin="<!-- BEGIN GENERATED $harness routing table -->"
        end="<!-- END GENERATED $harness routing table -->"
        block="$TMPDIR_WORK/$harness.md"
        out="$TMPDIR_WORK/out-$harness.md"
        if ! replace_marked_block "$work" "$out" "$begin" "$end" "$block"; then
            printf 'render-model-routing-docs: missing or malformed %s marker lines in %s\n' \
                "$harness" "$TARGET" >&2
            exit 1
        fi
        work="$out"
    done

    cp "$work" "$TARGET"
    printf 'Rendered routing tables into %s\n' "$TARGET"
}

main "$@"
