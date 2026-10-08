#!/bin/bash
# Integration test: verify uninstall.sh works (run after test-install.sh)
set -euo pipefail

echo "=== Testing speq-skill uninstallation in Docker ==="

# An unrelated skill in the shared Agent Skills directory must survive
mkdir -p ~/.agents/skills/speq-unrelated

# An agent the operator wrote next to the speq agents must survive
mkdir -p ~/.pi/agent/agents
echo "operator agent" > ~/.pi/agent/agents/speq-unrelated.md

# Run uninstall script
echo ""
echo "--- Running uninstall.sh ---"
./uninstall.sh

# Verify CLI binary removed
echo ""
echo "--- Verify CLI binary removed ---"
if [ -f ~/.local/bin/speq ]; then
    echo "FAIL: ~/.local/bin/speq still exists"
    exit 1
fi
echo "PASS: ~/.local/bin/speq removed"

# Verify marketplace directory removed
echo ""
echo "--- Verify marketplace directory removed ---"
if [ -d ~/.speq-skill ]; then
    echo "FAIL: ~/.speq-skill still exists"
    exit 1
fi
echo "PASS: ~/.speq-skill removed"

if [ -f ~/.codex/config.toml ] && grep -q '^\[marketplaces\.speq-skill-local\]' ~/.codex/config.toml; then
    echo "FAIL: Codex marketplace registration still exists"
    exit 1
fi
echo "PASS: Codex marketplace registration removed"

if [ -f ~/.agents/plugins/marketplace.json ] && grep -q '"name": "speq-skill"' ~/.agents/plugins/marketplace.json; then
    echo "FAIL: legacy Codex marketplace entry still exists"
    exit 1
fi
echo "PASS: legacy Codex marketplace entry removed"

if [ -e ~/.codex/skills/speq-plan ] || [ -L ~/.codex/skills/speq-plan ]; then
    echo "FAIL: Codex speq-plan skill still exists"
    exit 1
fi
echo "PASS: Codex skills removed"

if [[ -e ~/.agents/skills/speq-plan ]]; then
    echo "FAIL: Agent Skills speq-plan still exists"
    exit 1
fi
echo "PASS: Agent Skills (Pi) skills removed"

if [[ ! -d ~/.agents/skills/speq-unrelated ]]; then
    echo "FAIL: uninstall removed an Agent Skills entry it does not manage"
    exit 1
fi
echo "PASS: unmanaged Agent Skills entry kept"

if [[ -e ~/.pi/agent/agents/speq ]]; then
    echo "FAIL: Pi sub-agents still exist"
    exit 1
fi
echo "PASS: Pi sub-agents removed"

if [[ ! -f ~/.pi/agent/agents/speq-unrelated.md ]]; then
    echo "FAIL: uninstall removed a Pi agent it does not manage"
    exit 1
fi
echo "PASS: unmanaged Pi agent kept"

echo ""
echo "=== All uninstallation tests passed! ==="
