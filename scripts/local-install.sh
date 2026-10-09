#!/bin/bash
# Install speq-skill CLI and Claude/Codex plugin payloads from local build
# Usage: ./scripts/local-install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Shared helpers (info, warn, offer_mcp_servers, ...). install.sh only runs
# main when executed, so sourcing it defines functions and defaults only.
# The variables below override its defaults.
source "$PROJECT_ROOT/install.sh"

BIN_DIR="${HOME}/.local/bin"
MARKETPLACE_DIR="${PROJECT_ROOT}/dist/marketplace"
INSTALL_DIR="${HOME}/.speq-skill"
CODEX_MARKETPLACE_NAME="speq-skill-local"
CODEX_MARKETPLACE_ROOT="${INSTALL_DIR}/codex"
CODEX_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"

cd "$PROJECT_ROOT"

echo "=== Installing speq-skill ==="

# register_codex_plugin, install_codex_skills, install_agents_skills, and
# install_pi_agents all come from install.sh. They read MARKETPLACE_DIR, which
# points at the local build, and they only write: no override here may delete
# from the operator's tree.

# 1. Build release binary if not present
if [ ! -f "target/release/speq" ]; then
    echo "Building release binary..."
    cargo build --release
fi

# 2. Build plugin/marketplace
echo "Building plugin..."
./scripts/plugin/build.sh

# 3. Install CLI binary
mkdir -p "$BIN_DIR"
echo "Installing CLI to ${BIN_DIR}/speq..."
cp "target/release/speq" "$BIN_DIR/speq"
chmod +x "$BIN_DIR/speq"

# 4. Install Claude plugin via marketplace
if command -v claude &> /dev/null; then
    # Unregister the old plugin/marketplace first (idempotent for updates)
    claude plugin uninstall speq-skill@speq-skill 2>/dev/null || true
    claude plugin marketplace remove speq-skill 2>/dev/null || true

    echo "Adding speq-skill marketplace..."
    claude plugin marketplace add "$MARKETPLACE_DIR"

    echo "Installing speq-skill plugin..."
    claude plugin install speq-skill@speq-skill
else
    echo "Claude CLI not found, skipping Claude plugin registration"
fi

# 5. Install Codex plugin payload and skill copies. merge_tree overwrites the
# payload files and removes nothing.
merge_tree "$MARKETPLACE_DIR" "$INSTALL_DIR"
register_codex_plugin
install_codex_skills
install_agents_skills
install_pi_agents

# 5b. Serena comes from the global install
offer_mcp_servers

# 6. Verify installation
echo ""
echo "=== Installation complete ==="

if command -v speq &> /dev/null; then
    echo "CLI: $(which speq)"
else
    echo "CLI: ${BIN_DIR}/speq"
    echo "  Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo "Claude plugin: ${MARKETPLACE_DIR}"
echo "Codex plugin: ${INSTALL_DIR}/codex/plugins/speq-skill"
echo "Codex marketplace: ${CODEX_MARKETPLACE_ROOT}"
echo "Agent skills: ${AGENTS_SKILLS_DIR}"
echo "Pi agents: ${PI_AGENTS_DIR}"
echo ""
echo "To uninstall: ./uninstall.sh"
