#!/usr/bin/env bash
# speq-skill uninstaller
# Usage: curl -fsSL https://raw.githubusercontent.com/marconae/speq-skill/main/uninstall.sh | bash

set -e

INSTALL_DIR="$HOME/.local/bin"
MARKETPLACE_DIR="$HOME/.speq-skill"
CODEX_MARKETPLACE_NAME="speq-skill-local"
CODEX_LEGACY_MARKETPLACE_FILE="$HOME/.agents/plugins/marketplace.json"
CODEX_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
PI_AGENTS_DIR="$HOME/.pi/agent/agents/speq"
PI_SETTINGS_FILE="$HOME/.pi/agent/settings.json"
PI_OVERRIDES_MARKER="$PI_AGENTS_DIR/.speq-model-overrides"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}Warning:${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[${1}/${2}]${NC} $3"; }

remove_codex_plugin_with_python() {
    python3 - "$CODEX_LEGACY_MARKETPLACE_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() or not path.read_text().strip():
    raise SystemExit(0)

data = json.loads(path.read_text())
plugins = data.get("plugins")
if isinstance(plugins, list):
    data["plugins"] = [plugin for plugin in plugins if plugin.get("name") != "speq-skill"]
    path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

remove_codex_plugin_with_node() {
    node - "$CODEX_LEGACY_MARKETPLACE_FILE" <<'JS'
const fs = require("fs");
const file = process.argv[2];
if (!fs.existsSync(file) || !fs.readFileSync(file, "utf8").trim()) process.exit(0);
const data = JSON.parse(fs.readFileSync(file, "utf8"));
if (Array.isArray(data.plugins)) {
  data.plugins = data.plugins.filter((plugin) => plugin.name !== "speq-skill");
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
}
JS
}

remove_codex_plugin() {
    if command -v codex &> /dev/null; then
        if codex plugin marketplace remove "$CODEX_MARKETPLACE_NAME" >/dev/null 2>&1; then
            info "Removed Codex marketplace: $CODEX_MARKETPLACE_NAME"
        else
            warn "Codex marketplace not registered or already removed"
        fi
    else
        warn "Codex CLI not found, skipping Codex marketplace removal"
    fi

    if [[ ! -f "$CODEX_LEGACY_MARKETPLACE_FILE" ]]; then
        return
    elif command -v python3 &> /dev/null; then
        if remove_codex_plugin_with_python; then
            info "Removed legacy Codex marketplace entry from $CODEX_LEGACY_MARKETPLACE_FILE"
        else
            warn "Failed to update legacy Codex marketplace JSON with python3"
        fi
    elif command -v node &> /dev/null; then
        if remove_codex_plugin_with_node; then
            info "Removed legacy Codex marketplace entry from $CODEX_LEGACY_MARKETPLACE_FILE"
        else
            warn "Failed to update legacy Codex marketplace JSON with node"
        fi
    else
        warn "python3/node unavailable; remove speq-skill from $CODEX_LEGACY_MARKETPLACE_FILE manually"
    fi
}

remove_codex_skills() {
    if [[ ! -d "$CODEX_SKILLS_DIR" ]]; then
        warn "Codex skills directory not found, skipping Codex skill removal"
        return
    fi

    local removed=0
    for target in "$CODEX_SKILLS_DIR"/speq-*; do
        [[ -e "$target" || -L "$target" ]] || continue

        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" == "$MARKETPLACE_DIR/codex/plugins/speq-skill/skills/"* ]]; then
                rm -f "$target"
                removed=$((removed + 1))
            fi
        elif [[ -d "$target" && -f "$target/.speq-skill-managed" ]]; then
            rm -rf "$target"
            removed=$((removed + 1))
        fi
    done

    info "Removed $removed Codex skill installation(s) from $CODEX_SKILLS_DIR"
}

# Agent Skills (Pi and other Agent Skills hosts). Only copies that carry the
# marker file are removed, so unrelated skills in the shared directory stay.
remove_agents_skills() {
    if [[ ! -d "$AGENTS_SKILLS_DIR" ]]; then
        warn "Agent Skills directory not found, skipping Agent Skills removal"
        return
    fi

    local removed=0
    for target in "$AGENTS_SKILLS_DIR"/speq-*; do
        [[ -d "$target" ]] || continue

        if [[ -f "$target/.speq-skill-managed" ]]; then
            rm -rf "$target"
            removed=$((removed + 1))
        fi
    done

    info "Removed $removed Agent Skills installation(s) from $AGENTS_SKILLS_DIR"
}

# pi_json_writer_available reports whether perl can load its core JSON::PP
# module. The uninstaller degrades to a printed list of entries to remove when
# it cannot, so it never half-writes settings.json.
pi_json_writer_available() {
    command -v perl >/dev/null 2>&1 || return 1
    perl -MJSON::PP -e "1" >/dev/null 2>&1
}

# pi_update_settings applies "set<TAB>name<TAB>model" and "remove<TAB>name"
# operations from stdin to the settings document at $1 with perl's core
# JSON::PP module. It preserves every other key at every level, drops
# subagents.agentOverrides and subagents when a removal empties them,
# serializes with sorted keys and a two-space indent, and writes only when the
# serialized document differs from the file. The update goes through a
# temporary file and a rename, so a failed write leaves the original
# byte-identical. Exit status: 0 on success or no change, 3 when the document
# is invalid JSON, other non-zero when the document cannot be read or written.
# The same helper shape lives in install.sh.
pi_update_settings() {
    perl -MJSON::PP -e '
        use strict;
        use warnings;

        my $path = shift @ARGV;

        my @ops;
        while (my $line = <STDIN>) {
            chomp $line;
            next if $line eq "";
            my @fields = split /\t/, $line, 3;
            my $action = @fields > 0 ? $fields[0] : "";
            my $name   = @fields > 1 ? $fields[1] : "";
            next if $name eq "";
            if ($action eq "set" && @fields > 2) {
                push @ops, [ "set", $name, $fields[2] ];
            }
            elsif ($action eq "remove") {
                push @ops, [ "remove", $name ];
            }
        }

        my $exists = -e $path;
        my $original = "";
        my $data;
        if ($exists) {
            open my $in, "<", $path or die "cannot read $path: $!\n";
            binmode $in;
            local $/;
            $original = <$in>;
            close $in;
            $data = eval { JSON::PP->new->utf8->decode($original) };
            if ($@ || ref($data) ne "HASH") {
                print STDERR "invalid JSON\n";
                exit 3;
            }
        }
        else {
            $data = {};
        }

        my $removed = 0;
        my $sets = 0;
        for my $op (@ops) {
            my ($action, $name, $model) = @$op;
            if ($action eq "remove") {
                next unless ref($data->{subagents}) eq "HASH";
                next unless ref($data->{subagents}{agentOverrides}) eq "HASH";
                if (exists $data->{subagents}{agentOverrides}{$name}) {
                    delete $data->{subagents}{agentOverrides}{$name};
                    $removed++;
                }
                next;
            }
            if (exists $data->{subagents} && ref($data->{subagents}) ne "HASH") {
                print STDERR "subagents is not a JSON object; skipping $name\n";
                next;
            }
            $data->{subagents} = {} unless exists $data->{subagents};
            if (exists $data->{subagents}{agentOverrides} && ref($data->{subagents}{agentOverrides}) ne "HASH") {
                print STDERR "subagents.agentOverrides is not a JSON object; skipping $name\n";
                next;
            }
            $data->{subagents}{agentOverrides} = {} unless exists $data->{subagents}{agentOverrides};
            my $entry = $data->{subagents}{agentOverrides}{$name};
            if (exists $data->{subagents}{agentOverrides}{$name} && ref($entry) ne "HASH") {
                print STDERR "subagents.agentOverrides.$name is not a JSON object; skipping\n";
                next;
            }
            $data->{subagents}{agentOverrides}{$name} = {} unless exists $data->{subagents}{agentOverrides}{$name};
            $data->{subagents}{agentOverrides}{$name}{model} = $model;
            $sets++;
        }

        if ($removed) {
            if (ref($data->{subagents}) eq "HASH"
                && ref($data->{subagents}{agentOverrides}) eq "HASH"
                && !keys %{$data->{subagents}{agentOverrides}}) {
                delete $data->{subagents}{agentOverrides};
            }
            if (ref($data->{subagents}) eq "HASH" && !keys %{$data->{subagents}}) {
                delete $data->{subagents};
            }
        }

        exit 0 if !$exists && $sets == 0;

        my $codec = JSON::PP->new->canonical->utf8->pretty->indent_length(2);
        my $output = $codec->encode($data);
        $output .= "\n" unless $output =~ /\n$/;

        exit 0 if $exists && $output eq $original;

        my $tmp = "$path.speq-tmp.$$";
        my $mode;
        if ($exists) {
            my @st = stat $path;
            $mode = $st[2] & 07777 if @st;
        }
        open my $out, ">", $tmp or do {
            print STDERR "cannot create $tmp: $!\n";
            exit 4;
        };
        binmode $out;
        print {$out} $output or do {
            close $out;
            unlink $tmp;
            print STDERR "cannot write $tmp: $!\n";
            exit 4;
        };
        close $out or do {
            unlink $tmp;
            print STDERR "cannot write $tmp: $!\n";
            exit 4;
        };
        chmod $mode, $tmp if defined $mode;
        rename $tmp, $path or do {
            unlink $tmp;
            print STDERR "cannot replace $path: $!\n";
            exit 4;
        };
        exit 0;
    ' -- "$1"
}

# pi_remove_overrides removes the marker's names from settings.json. It never
# creates the file, and it degrades to a printed list when perl or JSON::PP is
# unavailable. It always returns 0: a settings problem never fails the
# uninstall.
pi_remove_overrides() {
    local names="$1"
    local name ops="" status=0

    [[ -n "$names" ]] || return 0

    # Nothing to remove when the file does not exist; never create it.
    [[ -f "$PI_SETTINGS_FILE" ]] || return 0

    if ! pi_json_writer_available; then
        warn "perl with JSON::PP is unavailable; remove these entries from $PI_SETTINGS_FILE manually:"
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            echo "  subagents.agentOverrides.$name"
        done <<< "$names"
        return 0
    fi

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        ops+="remove"$'\t'"$name"$'\n'
    done <<< "$names"

    printf '%s' "$ops" | pi_update_settings "$PI_SETTINGS_FILE" || status=$?
    case "$status" in
        0) : ;;
        3) warn "$PI_SETTINGS_FILE is not valid JSON; leaving it untouched" ;;
        *) warn "Failed to update $PI_SETTINGS_FILE; leaving it untouched" ;;
    esac
    return 0
}

# Pi sub-agents. The marker file lives inside the speq-owned directory, so an
# agent the operator wrote outside it is never removed. The marker is read
# before the directory is removed and lists the settings.json overrides the
# installer wrote, which are removed with it.
remove_pi_agents() {
    local previous=""

    if [[ -f "$PI_OVERRIDES_MARKER" ]]; then
        previous=$(cat "$PI_OVERRIDES_MARKER")
    fi

    if [[ -d "$PI_AGENTS_DIR" && -f "$PI_AGENTS_DIR/.speq-skill-managed" ]]; then
        rm -rf "$PI_AGENTS_DIR"
        info "Removed Pi sub-agents from $PI_AGENTS_DIR"
    else
        warn "Pi sub-agents not found, skipping Pi agent removal"
    fi

    pi_remove_overrides "$previous"
}

main() {
    echo ""
    echo "============================"
    echo "   speq-skill uninstaller"
    echo "============================"
    echo ""

    local total=8

    # Step 1: Uninstall Claude plugin
    step 1 $total "Removing Claude plugin..."
    if command -v claude &> /dev/null; then
        claude plugin uninstall speq-skill@speq-skill 2>/dev/null || warn "Plugin not installed or already removed"
    else
        warn "Claude CLI not found, skipping plugin removal"
    fi

    # Step 2: Remove marketplace registration
    step 2 $total "Removing marketplace registration..."
    if command -v claude &> /dev/null; then
        claude plugin marketplace remove speq-skill 2>/dev/null || warn "Marketplace not registered or already removed"
    else
        warn "Claude CLI not found, skipping marketplace removal"
    fi

    # Step 3: Remove Codex marketplace entry
    step 3 $total "Removing Codex marketplace entry..."
    remove_codex_plugin

    # Step 4: Remove Codex skills
    step 4 $total "Removing Codex skills..."
    remove_codex_skills

    # Step 5: Remove Agent Skills (Pi)
    step 5 $total "Removing Agent Skills..."
    remove_agents_skills

    # Step 6: Remove Pi sub-agents
    step 6 $total "Removing Pi sub-agents..."
    remove_pi_agents

    # Step 7: Remove CLI binary
    step 7 $total "Removing CLI binary..."
    if [ -f "$INSTALL_DIR/speq" ]; then
        rm -f "$INSTALL_DIR/speq"
        info "Removed $INSTALL_DIR/speq"
    else
        warn "$INSTALL_DIR/speq not found (already removed?)"
    fi

    # Step 8: Remove marketplace directory
    step 8 $total "Removing marketplace directory..."
    if [ -d "$MARKETPLACE_DIR" ]; then
        rm -rf "$MARKETPLACE_DIR"
        info "Removed $MARKETPLACE_DIR"
    else
        warn "$MARKETPLACE_DIR not found (already removed?)"
    fi

    echo ""
    info "Uninstall complete!"
    echo ""
    echo "Note: Rust toolchain was not removed (you may need it for other projects)."
    echo "To remove Rust: rustup self uninstall"
    echo ""
}

main "$@"
