#!/usr/bin/env bash
# Restricted-subset parser and lookup helpers for the model routing table.
#
# Source this file, then call routing_load on model-routing.yml at the
# repository root.
# The grammar is a line-oriented YAML subset: section headers, row names,
# plain properties, and one-level inline maps. Anything else is an error, so
# the build fails before it writes an artifact. See
# specs/_plans/add-model-routing-table/plan.md for the grammar contract.
#
# Bash 3.2 compatible: no associative arrays, no mapfile. Row fields live in
# dynamic variables named _ROUTING_<section>_<name>_<field>, with hyphens in
# names rewritten to underscores (row names match [a-z0-9-]*, so the rewrite
# cannot collide). A harness key loads as an empty string when its value is
# null, so callers treat absent and null alike: inject nothing. A load replaces
# the previous table: it clears every field variable an earlier load set before
# it records the new one.

# routing_load <file>
# Validates the table against the restricted subset and loads it. On a syntax
# or shape error it prints "<file>:<line>: <message>" followed by the
# offending line to stderr and returns 1.
routing_load() {
    local file="$1"
    local tmp
    local kind f1 f2 f3 f4 f5 value
    local var

    # A load replaces the previous table: clear every field variable an
    # earlier load recorded before this load records its own.
    for var in ${_ROUTING_FIELD_VARS-}; do
        unset "$var"
    done
    _ROUTING_FIELD_VARS=""

    if [[ ! -f "$file" ]]; then
        printf 'model-routing: no such routing table: %s\n' "$file" >&2
        return 1
    fi
    if [[ ! -s "$file" ]]; then
        printf '%s: routing table is empty\n' "$file" >&2
        return 1
    fi

    tmp=$(mktemp)
    if ! awk -v table="$file" "$(_routing_awk_program)" "$file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    _ROUTING_SOURCE="$file"
    _ROUTING_AGENTS_NAMES=""
    _ROUTING_SKILLS_NAMES=""

    while IFS=$'\t' read -r kind f1 f2 f3 f4 f5; do
        case "$kind" in
            R)
                if [[ "$f1" == "agents" ]]; then
                    _ROUTING_AGENTS_NAMES+="$f2 "
                elif [[ "$f1" == "skills" ]]; then
                    _ROUTING_SKILLS_NAMES+="$f2 "
                fi
                ;;
            A)
                var="_ROUTING_${f1}_${f2//-/_}_file"
                printf -v "$var" '%s' "$f3"
                _ROUTING_FIELD_VARS+="$var "
                ;;
            N)
                var="_ROUTING_${f1}_${f2//-/_}_note"
                printf -v "$var" '%s' "$f3"
                _ROUTING_FIELD_VARS+="$var "
                ;;
            V)
                value="$f5"
                if [[ "$value" == "null" ]]; then
                    value=""
                fi
                var="_ROUTING_${f1}_${f2//-/_}_${f3}_${f4}"
                printf -v "$var" '%s' "$value"
                _ROUTING_FIELD_VARS+="$var "
                ;;
        esac
    done < "$tmp"
    rm -f "$tmp"

    return 0
}

# _routing_awk_program prints the validator/emitter program. It lives in its
# own function because bash 3.2 mis-scans quotes in a here-document nested
# inside a command substitution.
_routing_awk_program() {
    cat <<'AWK'
function fail(lineno, msg, line) {
    printf "%s:%d: %s\n", table, lineno, msg > "/dev/stderr"
    printf "%s\n", line > "/dev/stderr"
    fatal = 1
    exit 1
}

function finish_row() {
    if (row == "") return
    if (!has_file)   fail(row_line, "row '" row "' has no file: property", row_text)
    if (!has_note)   fail(row_line, "row '" row "' has no note: property", row_text)
    if (!has_claude) fail(row_line, "row '" row "' has no claude: map", row_text)
    if (!has_codex)  fail(row_line, "row '" row "' has no codex: map", row_text)
    if (!has_pi)     fail(row_line, "row '" row "' has no pi: map", row_text)
    row = ""
}

BEGIN {
    TS = "\t"
    row = ""
    section = ""
}

{
    line = $0
    if (index(line, "\t") > 0) fail(NR, "tab characters are not allowed", line)

    indent = 0
    while (substr(line, indent + 1, 1) == " ") indent++
    content = substr(line, indent + 1)

    if (content == "" || substr(content, 1, 1) == "#") next

    if (indent == 0) {
        finish_row()
        if (content == "agents:") {
            if (seen_section["agents"]) fail(NR, "duplicate section 'agents:'", line)
            seen_section["agents"] = 1
            section = "agents"
        } else if (content == "skills:") {
            if (seen_section["skills"]) fail(NR, "duplicate section 'skills:'", line)
            seen_section["skills"] = 1
            section = "skills"
        } else {
            fail(NR, "unknown section header; expected 'agents:' or 'skills:'", line)
        }
        next
    }

    if (indent == 2) {
        if (section == "") fail(NR, "row outside a section", line)
        if (content !~ /^[a-z0-9][a-z0-9-]*:$/) {
            fail(NR, "row names must match [a-z0-9][a-z0-9-]* followed by ':'", line)
        }
        name = substr(content, 1, length(content) - 1)
        finish_row()
        if (seen_row[section, name]) fail(NR, "duplicate row '" name "' in section '" section "'", line)
        seen_row[section, name] = 1
        row = name
        row_line = NR
        row_text = line
        has_file = has_note = has_claude = has_codex = has_pi = 0
        printf "R%s%s%s%s\n", TS, section, TS, name
        next
    }

    if (indent != 4) fail(NR, "indentation must be 0, 2, or 4 spaces", line)
    if (row == "") fail(NR, "property line outside a row", line)

    colon = index(content, ":")
    if (colon == 0) fail(NR, "expected '<property>: <value>'", line)
    key = substr(content, 1, colon - 1)
    rest = substr(content, colon + 1)
    if (substr(rest, 1, 1) != " ") fail(NR, "expected a space after '" key ":'", line)
    sub(/^[ ]+/, "", rest)
    sub(/[ ]+$/, "", rest)
    if (key !~ /^[A-Za-z_-]+$/) fail(NR, "invalid property name '" key "'", line)
    if (rest == "") fail(NR, "property '" key "' has no value", line)

    if (key == "file") {
        if (has_file) fail(NR, "duplicate file: property in row '" row "'", line)
        has_file = 1
        if (section == "agents") expected = ".claude/agents/" row ".md"
        else expected = ".claude/skills/" row "/SKILL.md"
        if (rest != expected) fail(NR, "file: must be '" expected "'", line)
        printf "A%s%s%s%s%s%s\n", TS, section, TS, row, TS, rest
        next
    }

    if (key == "note") {
        if (has_note) fail(NR, "duplicate note: property in row '" row "'", line)
        if (index(rest, "|") > 0) fail(NR, "note: must not contain '|'", line)
        has_note = 1
        printf "N%s%s%s%s%s%s\n", TS, section, TS, row, TS, rest
        next
    }

    if (key != "claude" && key != "codex" && key != "pi") {
        fail(NR, "unknown property '" key "'; expected file, note, claude, codex, or pi", line)
    }
    if (key == "claude") { if (has_claude) fail(NR, "duplicate claude: map in row '" row "'", line); has_claude = 1 }
    if (key == "codex")  { if (has_codex)  fail(NR, "duplicate codex: map in row '" row "'", line);  has_codex = 1 }
    if (key == "pi")     { if (has_pi)     fail(NR, "duplicate pi: map in row '" row "'", line);     has_pi = 1 }

    if (rest !~ /^\{.*\}$/) fail(NR, key ": must be an inline map like { key: value }", line)
    inner = substr(rest, 2, length(rest) - 2)
    sub(/^[ ]+/, "", inner)
    sub(/[ ]+$/, "", inner)
    if (inner == "") next

    map_id++
    n = split(inner, parts, ",")
    for (i = 1; i <= n; i++) {
        part = parts[i]
        sub(/^[ ]+/, "", part)
        sub(/[ ]+$/, "", part)
        if (part == "") fail(NR, "empty entry in " key ": map", line)
        c = index(part, ":")
        if (c == 0) fail(NR, "flow-map entry '" part "' must be 'key: value'", line)
        fk = substr(part, 1, c - 1)
        fv = substr(part, c + 1)
        sub(/[ ]+$/, "", fk)
        sub(/^[ ]+/, "", fv)
        sub(/[ ]+$/, "", fv)
        if (fk !~ /^[A-Za-z_-]+$/) fail(NR, "invalid flow-map key '" fk "'", line)
        ok = 0
        if (key == "pi") { if (fk == "model" || fk == "thinking") ok = 1 }
        else { if (fk == "model" || fk == "effort") ok = 1 }
        if (!ok) fail(NR, "unknown flow-map key '" fk "' in " key ": map", line)
        if (mapseen[map_id, fk]) fail(NR, "duplicate flow-map key '" fk "' in " key ": map", line)
        mapseen[map_id, fk] = 1
        if (fv == "") fail(NR, "flow-map key '" fk "' has no value", line)
        if (fv ~ /^["']/) fail(NR, "quoted flow-map values are not supported", line)
        if (fv != "null" && fv !~ "^[A-Za-z0-9._/-]+$") {
            fail(NR, "invalid flow-map value '" fv "'", line)
        }
        printf "V%s%s%s%s%s%s%s%s%s%s\n", TS, section, TS, row, TS, key, TS, fk, TS, fv
    }
    next
}

END {
    if (fatal) exit 1
    finish_row()
    if (!seen_section["agents"]) fail(NR, "missing section 'agents:'", "")
    if (!seen_section["skills"]) fail(NR, "missing section 'skills:'", "")
}
AWK
}

# _routing_row_field <section> <name> <field>
# Prints one stored row field, or nothing when it is absent. Field is `file`,
# `note`, or `<harness>_<key>`.
_routing_row_field() {
    local var="_ROUTING_${1}_${2//-/_}_${3}"
    local value

    eval "value=\${$var-}"
    printf '%s' "$value"
}

# routing_value <section> <name> <harness> <key>
# Prints the value, or nothing when the key is absent or null. A harness map
# that is empty injects nothing and lets the harness inherit its default.
routing_value() {
    _routing_row_field "$1" "$2" "${3}_${4}"
}

# _routing_names_raw <section>
# Prints the section's space-separated name list in table order.
_routing_names_raw() {
    case "$1" in
        agents) printf '%s' "${_ROUTING_AGENTS_NAMES-}" ;;
        skills) printf '%s' "${_ROUTING_SKILLS_NAMES-}" ;;
    esac
}

# routing_names <section>
# Prints the row names of a section in table order, one per line.
routing_names() {
    local names
    local name

    names=$(_routing_names_raw "$1")
    for name in $names; do
        printf '%s\n' "$name"
    done
}

# routing_note <section> <name>
# Prints the row's note.
routing_note() {
    _routing_row_field "$1" "$2" note
}

# _routing_has_name <section> <name>
# Returns 0 when the section has a row with that name.
_routing_has_name() {
    local names

    names=$(_routing_names_raw "$1")
    case " $names " in
        *" $2 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# routing_check_coverage <source-dir>
# Fails when the table and the source tree disagree: a source agent or skill
# with no row names the source file; a row whose file is absent names the row
# and the expected path. The source directory is the .claude tree that holds
# agents/ and skills/.
routing_check_coverage() {
    local source_dir="$1"
    local root
    local table="${_ROUTING_SOURCE:-model-routing.yml}"
    local failed=0
    local section names name expected rel file

    # The table's file: values are repository-relative, so they resolve
    # against the parent of the .claude source directory.
    root=$(dirname "$source_dir")

    for section in agents skills; do
        names=$(_routing_names_raw "$section")
        for name in $names; do
            rel=$(_routing_row_field "$section" "$name" file)
            expected="$root/$rel"
            if [[ ! -f "$expected" ]]; then
                printf "%s: row '%s' expects '%s', but the file is absent\n" \
                    "$table" "$name" "$rel" >&2
                failed=1
            fi
        done
    done

    if [[ -d "$source_dir/agents" ]]; then
        for file in "$source_dir/agents"/*.md; do
            [[ -f "$file" ]] || continue
            name=$(basename "$file" .md)
            if ! _routing_has_name agents "$name"; then
                printf '%s: no routing row for %s\n' "$table" "$file" >&2
                failed=1
            fi
        done
    fi

    if [[ -d "$source_dir/skills" ]]; then
        for file in "$source_dir/skills"/speq-*/SKILL.md; do
            [[ -f "$file" ]] || continue
            name=$(basename "$(dirname "$file")")
            if ! _routing_has_name skills "$name"; then
                printf '%s: no routing row for %s\n' "$table" "$file" >&2
                failed=1
            fi
        done
    fi

    return $failed
}
