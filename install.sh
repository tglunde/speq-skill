#!/usr/bin/env bash
# speq-skill installer
# Usage: curl -fsSL https://raw.githubusercontent.com/marconae/speq-skill/main/install.sh | bash

set -e

REPO="marconae/speq-skill"
INSTALL_DIR="$HOME/.local/bin"
MARKETPLACE_DIR="$HOME/.speq-skill"
CODEX_MARKETPLACE_NAME="speq-skill-local"
CODEX_MARKETPLACE_ROOT="$MARKETPLACE_DIR/codex"
CODEX_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
# `--open-web-dashboard false` keeps Serena's dashboard available but stops it
# from opening a browser window every time the harness starts a session.
CODEX_SERENA_ADD="codex mcp add serena -- serena start-mcp-server --project-from-cwd --context=codex --open-web-dashboard false"
CLAUDE_SERENA_ADD="claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false"
# Pi has no dedicated Serena context; `ide` is the generic coding-agent one.
PI_SERENA_ADD="pi mcp add serena -- serena start-mcp-server --project-from-cwd --context=ide --open-web-dashboard false"
# Pi reads the shared Agent Skills location. The installer writes Pi's own
# copies there, and its sub-agents into the directory Pi discovers.
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
PI_AGENTS_DIR="$HOME/.pi/agent/agents/speq"
PI_MCP_CONFIG="$HOME/.pi/agent/mcp.json"
PI_SETTINGS_FILE="$HOME/.pi/agent/settings.json"
# The Pi provider configuration files pi_provider_is_configured reads. Pi names
# a provider at the top level of its credential store and its catalog cache,
# and under `providers` in the operator's own model declarations.
PI_AUTH_FILE="$HOME/.pi/agent/auth.json"
PI_MODELS_FILE="$HOME/.pi/agent/models.json"
PI_MODELS_STORE_FILE="$HOME/.pi/agent/models-store.json"
PI_OVERRIDES_ARTIFACT="$MARKETPLACE_DIR/pi/model-overrides.json"
PI_OVERRIDES_MARKER="$PI_AGENTS_DIR/.speq-model-overrides"
SERENA_CLI_INSTALL="uv tool install -p 3.13 serena-agent"

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

# Get latest release tag from GitHub API
get_latest_version() {
    local response
    response=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null) || {
        warn "No releases found, using main branch" >&2
        echo "main"
        return
    }
    echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

register_codex_plugin() {
    if [[ ! -f "$CODEX_MARKETPLACE_ROOT/.agents/plugins/marketplace.json" ]]; then
        warn "Codex plugin payload missing; skipping Codex registration"
        return
    fi

    if command -v codex &> /dev/null; then
        info "Registering Codex marketplace..."
        codex plugin marketplace remove "$CODEX_MARKETPLACE_NAME" >/dev/null 2>&1 || true
        if codex plugin marketplace add "$CODEX_MARKETPLACE_ROOT" >/dev/null 2>&1; then
            info "Registered Codex marketplace: $CODEX_MARKETPLACE_NAME"
        else
            warn "Codex marketplace registration failed."
            echo "  Run manually: codex plugin marketplace add $CODEX_MARKETPLACE_ROOT"
        fi
    else
        warn "Codex CLI not found. Register the marketplace after installing Codex:"
        echo "  codex plugin marketplace add $CODEX_MARKETPLACE_ROOT"
    fi
}

install_codex_skills() {
    local source_dir="$MARKETPLACE_DIR/codex/plugins/speq-skill/skills"

    if [[ ! -d "$source_dir" ]]; then
        warn "Codex skills payload missing; skipping Codex skill installation"
        return
    fi

    mkdir -p "$CODEX_SKILLS_DIR"

    for skill_dir in "$source_dir"/*; do
        [[ -d "$skill_dir" ]] || continue

        local skill_name
        local target
        skill_name=$(basename "$skill_dir")
        target="$CODEX_SKILLS_DIR/speq-$skill_name"

        if [[ -L "$target" ]]; then
            rm -f "$target"
        elif [[ -d "$target" && -f "$target/.speq-skill-managed" ]]; then
            rm -rf "$target"
        elif [[ -e "$target" ]]; then
            warn "Codex skill already exists and is not managed by speq-skill, skipping: $target"
            continue
        fi

        cp -R "$skill_dir" "$target"
        touch "$target/.speq-skill-managed"
    done

    info "Installed Codex /speq:* skills into $CODEX_SKILLS_DIR"
}

# Pi's payload already carries the prefixed skill names (`speq-<name>`), the
# `/skill:speq-<name>` invocations, Pi's tool names, and the Pi host note, so
# these copies need no rewriting. The payload is the skill tree the build
# produced; this function only places it where Pi reads it.
install_agents_skills() {
    local source_dir="$MARKETPLACE_DIR/pi/skills"

    if [[ ! -d "$source_dir" ]]; then
        warn "Pi skill payload missing; skipping Agent Skills installation"
        return
    fi

    mkdir -p "$AGENTS_SKILLS_DIR"

    for skill_dir in "$source_dir"/*; do
        [[ -d "$skill_dir" ]] || continue

        local target
        target="$AGENTS_SKILLS_DIR/$(basename "$skill_dir")"

        if [[ -L "$target" ]]; then
            rm -f "$target"
        elif [[ -d "$target" && -f "$target/.speq-skill-managed" ]]; then
            rm -rf "$target"
        elif [[ -e "$target" ]]; then
            warn "Skill already exists and is not managed by speq-skill, skipping: $target"
            continue
        fi

        cp -R "$skill_dir" "$target"
        touch "$target/.speq-skill-managed"
    done

    info "Installed Agent Skills into $AGENTS_SKILLS_DIR (Pi: /skill:speq-*)"
}

# pi_json_writer_available reports whether perl can load its core JSON::PP
# module. Both the installer and the uninstaller degrade to a printed snippet
# when it cannot, so neither ever half-writes settings.json.
pi_json_writer_available() {
    command -v perl >/dev/null 2>&1 || return 1
    perl -MJSON::PP -e "1" >/dev/null 2>&1
}

# pi_update_settings applies "set<TAB>name<TAB>model" and "remove<TAB>name"
# operations from stdin to the settings document at $1 with perl's core
# JSON::PP module. It preserves every other key at every level, serializes with
# sorted keys and a two-space indent, and writes only when the serialized
# document differs from the file. The update goes through a temporary file and
# a rename, so a failed write leaves the original byte-identical. Exit status:
# 0 on success or no change, 3 when the document is invalid JSON, other
# non-zero when the document cannot be read or written. The same helper shape
# lives in uninstall.sh.
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

# pi_artifact_pins prints one "name<TAB>model" line per override in the
# generated artifact. It returns non-zero when the file exists but is not a
# flat object of quoted string pairs, so a malformed payload never rewrites
# the operator's entries.
pi_artifact_pins() {
    local artifact="$1"

    [[ -f "$artifact" ]] || return 0

    awk '
        { buf = buf $0 }
        END {
            gsub(/^[[:space:]]+/, "", buf)
            gsub(/[[:space:]]+$/, "", buf)
            if (buf == "" || buf == "{}") exit 0
            if (substr(buf, 1, 1) != "{" || substr(buf, length(buf), 1) != "}") exit 1
            inner = substr(buf, 2, length(buf) - 2)
            count = split(inner, pairs, /[[:space:]]*,[[:space:]]*/)
            for (i = 1; i <= count; i++) {
                pair = pairs[i]
                if (pair ~ /^[[:space:]]*$/) continue
                if (pair !~ /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*$/) exit 1
                key = pair
                sub(/^[[:space:]]*"/, "", key)
                sub(/".*$/, "", key)
                value = pair
                sub(/^[^:]*:[[:space:]]*"/, "", value)
                sub(/"[[:space:]]*$/, "", value)
                print key "\t" value
            }
        }
    ' "$artifact"
}

# pi_list_contains returns 0 when $2 is one of the newline-separated names in $1.
pi_list_contains() {
    local names="$1"
    local name="$2"

    [[ -n "$names" ]] || return 1
    printf '%s\n' "$names" | grep -qxF -- "$name"
}

# pi_write_marker records the override names the installer owns. An empty set
# writes an empty marker, so a later install knows the previous set is gone.
pi_write_marker() {
    if [[ -n "$1" ]]; then
        printf '%s\n' "$1" > "$PI_OVERRIDES_MARKER"
    else
        : > "$PI_OVERRIDES_MARKER"
    fi
}

# pi_print_override_json prints the settings fragment an operator can paste
# when perl or JSON::PP is unavailable.
pi_print_override_json() {
    local pins="$1"
    local name model sep=""

    echo "{"
    echo "  \"subagents\": {"
    echo "    \"agentOverrides\": {"
    while IFS=$'\t' read -r name model; do
        [[ -n "$name" ]] || continue
        printf '%s      "%s": { "model": "%s" }' "$sep" "$name" "$model"
        sep=$',\n'
    done <<< "$pins"
    echo ""
    echo "    }"
    echo "  }"
    echo "}"
}

# pi_provider_is_configured returns 0 when the operator's Pi configuration
# names $1 as a provider: as a top-level key of the credential store or the
# catalog cache, or under `providers` in the operator's own model
# declarations. It returns 1 when no such file exists, when the provider is
# absent from all of them, and when a file cannot be read or decoded. A caller
# therefore skips a pin it cannot verify rather than writing one the operator
# cannot run.
pi_provider_is_configured() {
    local provider="$1"
    local file

    [[ -n "$provider" ]] || return 1

    for file in "$PI_AUTH_FILE" "$PI_MODELS_FILE" "$PI_MODELS_STORE_FILE"; do
        [[ -f "$file" ]] || continue
        if perl -MJSON::PP -e '
            use strict;
            use warnings;

            my $path = shift @ARGV;
            my $provider = shift @ARGV;

            open my $in, "<", $path or exit 1;
            binmode $in;
            local $/;
            my $text = <$in>;
            close $in;

            my $data = eval { JSON::PP->new->utf8->decode($text) };
            exit 1 if $@ || ref($data) ne "HASH";
            exit 0 if exists $data->{$provider};
            exit 0 if ref($data->{providers}) eq "HASH"
                && exists $data->{providers}{$provider};
            exit 1;
        ' -- "$file" "$provider" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

# pi_reconcile_overrides applies the artifact's pins to the operator's
# settings.json, removes the previous marker's names the artifact no longer
# pins, and rewrites the marker. $1 = previous marker contents, $2 = pins
# ("name<TAB>model" lines).
pi_reconcile_overrides() {
    local previous="$1"
    local pins="$2"
    local names removes ops name model provider filtered status writer_ok=0

    if pi_json_writer_available; then
        writer_ok=1
    fi

    # A provider-qualified pin reaches settings.json only when the operator
    # has that provider configured, so the shipped table's vendor choices
    # never land on an operator who cannot run them. Filtering here, before
    # the marker names are derived, means a pin skipped this way also removes
    # the override an earlier install wrote for it. A bare model id names no
    # provider and is never gated. The check needs perl, the same dependency
    # the write below needs, so an operator without it keeps the previous
    # behavior: every pin is offered as a manual instruction.
    if [[ $writer_ok -eq 1 ]]; then
        filtered=""
        while IFS=$'\t' read -r name model; do
            [[ -n "$name" ]] || continue
            case "$model" in
                */*)
                    provider="${model%%/*}"
                    if ! pi_provider_is_configured "$provider"; then
                        warn "Skipping the $name override: provider '$provider' is not configured for Pi"
                        continue
                    fi
                    ;;
            esac
            filtered+="$name"$'\t'"$model"$'\n'
        done <<< "$pins"
        pins="$filtered"
    fi

    names=$(printf '%s\n' "$pins" | cut -f1)

    removes=""
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if ! pi_list_contains "$names" "$name"; then
            removes+="$name"$'\n'
        fi
    done <<< "$previous"

    ops=""
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        ops+="remove"$'\t'"$name"$'\n'
    done <<< "$removes"
    while IFS=$'\t' read -r name model; do
        [[ -n "$name" ]] || continue
        ops+="set"$'\t'"$name"$'\t'"$model"$'\n'
    done <<< "$pins"

    if [[ -z "$ops" ]]; then
        # Nothing pinned and nothing recorded: settings.json stays untouched.
        pi_write_marker ""
        return 0
    fi

    if [[ ! -f "$PI_SETTINGS_FILE" && -z "$pins" ]]; then
        # Only stale names to remove and no file to remove them from: never
        # create settings.json just to prune it.
        pi_write_marker ""
        return 0
    fi

    if [[ $writer_ok -eq 0 ]]; then
        warn "perl with JSON::PP is unavailable; not updating $PI_SETTINGS_FILE"
        if [[ -n "$pins" ]]; then
            echo "Add these overrides to $PI_SETTINGS_FILE manually:"
            pi_print_override_json "$pins"
        fi
        if [[ -n "$removes" ]]; then
            echo "Remove these overrides from $PI_SETTINGS_FILE manually:"
            while IFS= read -r name; do
                [[ -n "$name" ]] || continue
                echo "  subagents.agentOverrides.$name"
            done <<< "$removes"
        fi
        return 0
    fi

    mkdir -p "$(dirname "$PI_SETTINGS_FILE")"

    # Only a completed merge rewrites the marker. A degraded or failed update
    # wrote nothing, so it records nothing and a later uninstall removes only
    # what the installer actually owns.
    status=0
    printf '%s' "$ops" | pi_update_settings "$PI_SETTINGS_FILE" || status=$?
    case "$status" in
        0) pi_write_marker "$names" ;;
        3) warn "$PI_SETTINGS_FILE is not valid JSON; leaving it untouched" ;;
        *) warn "Failed to update $PI_SETTINGS_FILE; leaving it untouched" ;;
    esac
    return 0
}

# Pi discovers sub-agents under ~/.pi/agent/agents/. They live in their own
# directory so one marker file covers the whole install and removal cannot
# touch an agent the operator wrote. The same directory carries the marker for
# the model overrides the installer wrote, which is read before the directory
# is replaced and rewritten after the reconcile.
install_pi_agents() {
    local source_dir="$MARKETPLACE_DIR/pi/agents"
    local previous=""
    local pins=""
    local artifact_ok=1

    if [[ ! -d "$source_dir" ]]; then
        warn "Pi agent payload missing; skipping Pi agent installation"
        return
    fi

    if [[ -e "$PI_AGENTS_DIR" && ! -f "$PI_AGENTS_DIR/.speq-skill-managed" ]]; then
        warn "Pi agent directory exists and is not managed by speq-skill, skipping: $PI_AGENTS_DIR"
        return
    fi

    if [[ -f "$PI_OVERRIDES_MARKER" ]]; then
        previous=$(cat "$PI_OVERRIDES_MARKER")
    fi
    if ! pins=$(pi_artifact_pins "$PI_OVERRIDES_ARTIFACT"); then
        warn "Unrecognized Pi model overrides artifact; skipping Pi model overrides: $PI_OVERRIDES_ARTIFACT"
        artifact_ok=0
    fi

    rm -rf "$PI_AGENTS_DIR"
    mkdir -p "$PI_AGENTS_DIR"
    cp "$source_dir"/*.md "$PI_AGENTS_DIR/"
    touch "$PI_AGENTS_DIR/.speq-skill-managed"

    if [[ $artifact_ok -eq 1 ]]; then
        pi_reconcile_overrides "$previous" "$pins"
    fi

    info "Installed Pi sub-agents into $PI_AGENTS_DIR"
}

# Detect platform triple understood by the release archive naming convention
detect_platform() {
    local arch os
    arch=$(uname -m)
    os=$(uname -s)

    case "$arch" in
        x86_64)        arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *)             echo ""; return ;;
    esac

    case "$os" in
        Linux)  os="linux" ;;
        Darwin) os="mac" ;;
        *)      echo ""; return ;;
    esac

    echo "${arch}-${os}"
}

# Download a pre-built release archive and install it directly (no compilation).
# Returns 0 on success, 1 if no pre-built binary is available for this platform
# or if the download fails.
install_from_prebuilt() {
    local version="$1"

    # When a local source tarball is provided (Docker test mode), always compile
    [[ -n "${SPEQ_LOCAL_TARBALL:-}" ]] && return 1

    local platform
    platform=$(detect_platform)
    [[ -z "$platform" ]] && return 1

    # Strip leading 'v' for crate version, but the tag name is used in the asset URL
    local archive_name="speq-marketplace-${version}-${platform}.tar.gz"
    local download_url="https://github.com/$REPO/releases/download/${version}/${archive_name}"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" RETURN

    info "Downloading pre-built binary for ${platform}..."
    if ! curl -fsSL "$download_url" -o "$tmp_dir/release.tar.gz" 2>/dev/null; then
        warn "No pre-built binary available for ${platform} (${version})."
        return 1
    fi

    step 1 3 "Extracting..."
    tar -xzf "$tmp_dir/release.tar.gz" -C "$tmp_dir"

    local extract_dir="$tmp_dir/speq-marketplace-${version}-${platform}"

    step 2 3 "Installing..."

    mkdir -p "$INSTALL_DIR"
    cp "$extract_dir/bin/speq" "$INSTALL_DIR/speq"
    chmod +x "$INSTALL_DIR/speq"
    info "Installed speq to $INSTALL_DIR/speq"

    rm -rf "$MARKETPLACE_DIR"
    mkdir -p "$MARKETPLACE_DIR"
    cp -r "$extract_dir/." "$MARKETPLACE_DIR/"
    info "Installed marketplace to $MARKETPLACE_DIR"

    step 3 3 "Registering plugins..."

    if command -v claude &> /dev/null; then
        info "Registering plugin with Claude CLI..."
        claude plugin uninstall speq-skill@speq-skill 2>/dev/null || true
        claude plugin marketplace remove speq-skill 2>/dev/null || true
        claude plugin marketplace add "$MARKETPLACE_DIR" 2>/dev/null || true
        claude plugin install speq-skill@speq-skill 2>/dev/null || true
    else
        warn "Claude CLI not found. Run these commands after installing Claude:"
        echo "  claude plugin marketplace add $MARKETPLACE_DIR"
        echo "  claude plugin install speq-skill@speq-skill"
    fi

    register_codex_plugin
    install_codex_skills
    install_agents_skills
    install_pi_agents

    return 0
}

# Download and build from source
#
# Environment variables for testing:
#   SPEQ_LOCAL_TARBALL - Path to local source tarball (skips GitHub download)
#   SPEQ_PREBUILT      - If set and target/release/speq exists, skip cargo build
#
build_from_source() {
    local version="$1"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    # Support local tarball for testing (skips GitHub download)
    if [[ -n "${SPEQ_LOCAL_TARBALL:-}" ]]; then
        step 1 5 "Using local tarball: $SPEQ_LOCAL_TARBALL"
        cp "$SPEQ_LOCAL_TARBALL" "$tmp_dir/source.tar.gz"
    else
        local archive_url
        if [[ "$version" == "main" ]]; then
            archive_url="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
        else
            archive_url="https://github.com/$REPO/archive/refs/tags/${version}.tar.gz"
        fi
        step 1 5 "Downloading speq-skill ${version}..."
        curl -fsSL "$archive_url" -o "$tmp_dir/source.tar.gz"
    fi

    step 2 5 "Extracting source..."
    tar -xzf "$tmp_dir/source.tar.gz" -C "$tmp_dir"
    cd "$tmp_dir"/speq-skill-*

    # Support pre-built binary (skips cargo build)
    if [[ -n "${SPEQ_PREBUILT:-}" ]] && [[ -f "target/release/speq" ]]; then
        step 3 5 "Using pre-built binary..."
    else
        step 3 5 "Building from source (this may take a moment)..."
        cargo build --release
    fi

    step 4 5 "Building plugin..."
    ./scripts/plugin/build.sh

    step 5 5 "Installing..."

    # Install binary
    mkdir -p "$INSTALL_DIR"
    cp target/release/speq "$INSTALL_DIR/speq"
    chmod +x "$INSTALL_DIR/speq"
    info "Installed speq to $INSTALL_DIR/speq"

    # Install marketplace (use /. to include hidden files like .claude-plugin)
    rm -rf "$MARKETPLACE_DIR"
    mkdir -p "$MARKETPLACE_DIR"
    cp -r dist/marketplace/. "$MARKETPLACE_DIR/"
    mkdir -p "$MARKETPLACE_DIR/bin"
    cp target/release/speq "$MARKETPLACE_DIR/bin/speq"
    chmod +x "$MARKETPLACE_DIR/bin/speq"

    # Register with Claude CLI
    if command -v claude &> /dev/null; then
        info "Registering plugin with Claude CLI..."
        # Unregister old plugin/marketplace first (idempotent for updates)
        claude plugin uninstall speq-skill@speq-skill 2>/dev/null || true
        claude plugin marketplace remove speq-skill 2>/dev/null || true
        claude plugin marketplace add "$MARKETPLACE_DIR" 2>/dev/null || true
        claude plugin install speq-skill@speq-skill 2>/dev/null || true
    else
        warn "Claude CLI not found. Run these commands after installing Claude:"
        echo "  claude plugin marketplace add $MARKETPLACE_DIR"
        echo "  claude plugin install speq-skill@speq-skill"
    fi

    # Register with Codex marketplace
    register_codex_plugin
    install_codex_skills

    # Install Agent Skills and sub-agents (Pi)
    install_agents_skills
    install_pi_agents
}

# Resolve the platform-native cache directory, mirroring the `dirs` crate's
# split used by the speq binary's own get_cache_path(): macOS uses
# ~/Library/Caches, everything else follows the XDG convention.
default_cache_dir() {
    local os
    os=$(uname -s)
    case "$os" in
        Darwin) echo "$HOME/Library/Caches" ;;
        *)      echo "${XDG_CACHE_HOME:-$HOME/.cache}" ;;
    esac
}

# Serena comes from the user's global install. The helpers below detect it and
# offer to install or enable it. They never install silently. Context7 is not
# managed here: the skills use it when it is there.
#
# Prompts read from /dev/tty, not stdin, so they also work under
# `curl ... | bash`. SPEQ_TTY overrides the device (used by the tests).
has_tty() { { : < "${SPEQ_TTY:-/dev/tty}"; } 2>/dev/null; }

ask_yes_no() {
    has_tty || return 1
    local reply
    read -p "$1 [y/N] " -n 1 -r reply < "${SPEQ_TTY:-/dev/tty}" || return 1
    echo ""
    [[ $reply =~ ^[Yy]$ ]]
}

# Make sure the Serena CLI exists for the MCP registration.
ensure_serena_cli() {
    command -v serena &> /dev/null && return 0

    if command -v uv &> /dev/null; then
        info "Installing Serena CLI via uv..."
        if $SERENA_CLI_INSTALL >/dev/null 2>&1; then
            return 0
        fi
        warn "Serena CLI installation failed."
        echo "  Run manually: $SERENA_CLI_INSTALL"
    else
        warn "uv not found. Install uv, then install the Serena CLI:"
        echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo "  $SERENA_CLI_INSTALL"
    fi
    return 1
}

# offer_action <verb> <past-tense> <server> <host> <command> [prepare-function]
offer_action() {
    local verb="$1" past="$2" server="$3" host="$4" command="$5" prepare="${6:-}"

    if ! ask_yes_no "$verb $server for $host?"; then
        if ! has_tty; then
            warn "$server is not $(echo "$past" | tr 'A-Z' 'a-z') for $host. Run:"
            if [[ -n "$prepare" ]] && ! command -v serena &> /dev/null; then
                echo "  $SERENA_CLI_INSTALL"
            fi
            echo "  $command"
        fi
        return 0
    fi

    if [[ -n "$prepare" ]] && ! $prepare; then
        return 0
    fi

    if $command >/dev/null 2>&1; then
        info "$past $server for $host"
    else
        warn "$verb $server for $host failed."
        echo "  Run manually: $command"
    fi
    return 0
}

# Serena counts as installed for Claude Code when it is registered as an MCP
# server (any scope) or when a Serena plugin is enabled.
claude_has_serena() {
    claude mcp get serena >/dev/null 2>&1 && return 0
    claude plugin list 2>/dev/null | awk '
        /❯/ { cur = ($2 ~ /^serena@/) }
        cur && /Status:/ { found = ($0 !~ /✘|disabled/); exit }
        END { exit !found }'
}

# Pi keeps its servers in ~/.pi/agent/mcp.json. Reading that file is cheaper
# and quieter than `pi mcp list`, which connects to every configured server.
pi_has_serena() {
    [[ -f "$PI_MCP_CONFIG" ]] || return 1
    grep -Eq '"serena"[[:space:]]*:' "$PI_MCP_CONFIG"
}

offer_mcp_servers() {
    if command -v claude &> /dev/null && ! claude_has_serena; then
        offer_action Install Installed serena "Claude Code" "$CLAUDE_SERENA_ADD" ensure_serena_cli
    fi

    if command -v codex &> /dev/null && ! codex mcp get serena >/dev/null 2>&1; then
        offer_action Install Installed serena "Codex" "$CODEX_SERENA_ADD" ensure_serena_cli
    fi

    if command -v pi &> /dev/null && ! pi_has_serena; then
        offer_action Install Installed serena "Pi" "$PI_SERENA_ADD" ensure_serena_cli
    fi
    return 0
}

provision_embedding_model() {
    local HUGGINGFACE_BASE="https://huggingface.co/Snowflake/snowflake-arctic-embed-xs/resolve/main"

    if [[ -n "${SPEQ_CACHE_DIR:-}" ]]; then
        local MODEL_DIR="${SPEQ_CACHE_DIR}/models"
    else
        local cache_dir
        cache_dir=$(default_cache_dir)
        local MODEL_DIR="${cache_dir}/speq/models"
    fi

    local files=("model.onnx" "tokenizer.json")

    local all_cached=true
    for filename in "${files[@]}"; do
        [[ -f "$MODEL_DIR/$filename" ]] || { all_cached=false; break; }
    done
    if [[ "$all_cached" == true ]]; then
        info "Embedding model already provisioned in $MODEL_DIR"
        return 0
    fi

    # Drop any previously provisioned model files so upgrades always get a fresh copy
    if [[ -d "$MODEL_DIR" ]]; then
        for filename in "${files[@]}"; do
            rm -f "$MODEL_DIR/$filename"
        done
    fi

    info "Provisioning embedding model into $MODEL_DIR..."
    mkdir -p "$MODEL_DIR"

    for filename in "${files[@]}"; do
        local dest="$MODEL_DIR/$filename"
        local url
        case "$filename" in
            model.onnx) url="$HUGGINGFACE_BASE/onnx/model.onnx" ;;
            *)          url="$HUGGINGFACE_BASE/$filename" ;;
        esac
        if ! curl -fsSL "$url" -o "${dest}.tmp"; then
            rm -f "${dest}.tmp"
            echo ""
            echo -e "${RED}Error:${NC} Failed to download $filename from HuggingFace."
            echo "  To provision manually: curl -fsSL \"$url\" -o \"$MODEL_DIR/$filename\""
            echo ""
            exit 1
        fi
        mv "${dest}.tmp" "$dest"
    done

    info "Embedding model provisioned in $MODEL_DIR"
}

# Check if ~/.local/bin is in PATH
check_path() {
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        warn "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi
}

main() {
    echo ""
    echo "=========================="
    echo "   speq-skill installer"
    echo "=========================="
    echo ""

    # Get version
    info "Checking for latest release..."
    local version
    version=$(get_latest_version)
    info "Installing version: $version"
    echo ""

    # Pre-built binary only. The local tarball is the Docker test hook.
    if ! install_from_prebuilt "$version"; then
        if [[ -n "${SPEQ_LOCAL_TARBALL:-}" ]]; then
            build_from_source "$version"
        else
            error "No pre-built binary for this platform. Build speq-skill from source: https://github.com/$REPO/blob/main/docs/installation.md#install-from-source"
        fi
    fi

    # Serena comes from the global install
    offer_mcp_servers

    # Provision embedding model
    provision_embedding_model

    # Post-install checks
    check_path

    echo ""
    echo "========================================"
    info "Installation complete!"
    echo "========================================"
    echo ""
    echo "  Binary:      $INSTALL_DIR/speq"
    echo "  Plugin:      $MARKETPLACE_DIR/"
    echo "  Codex:       $CODEX_MARKETPLACE_ROOT"
    echo "  Agent skills: $AGENTS_SKILLS_DIR"
    echo "  Pi agents:   $PI_AGENTS_DIR"
    if command -v claude &> /dev/null; then
        echo "  Claude CLI:  plugin registered"
    else
        echo "  Claude CLI:  not found (register manually after installing)"
    fi
    if command -v codex &> /dev/null; then
        echo "  Codex CLI:   marketplace registered"
    else
        echo "  Codex CLI:   not found (marketplace entry created)"
    fi
    if command -v pi &> /dev/null; then
        echo "  Pi CLI:      skills (/skill:speq-*) and agents installed"
    else
        echo "  Pi CLI:      not found (skills and agents installed for later)"
    fi
    echo ""
    echo "Run 'speq --help' to get started."
    echo ""
}

if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
