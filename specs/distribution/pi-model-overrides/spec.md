# Feature: Pi Model Overrides

The installer pins the routing table's Pi models for the installed sub-agents through Pi settings overrides, and the uninstaller removes exactly those entries.

## Background

- Pi resolves a sub-agent's model from `subagents.agentOverrides.<name>.model` in `~/.pi/agent/settings.json` before the agent's frontmatter.
- The plugin build emits the pinned models as `pi/model-overrides.json` in the Pi payload. An empty object means no agent is pinned.
- `settings.json` belongs to the operator and can hold unrelated keys. It may be absent or hold an invalid document.
- The installer creates `settings.json` only when it pins at least one model; both tools warn and leave an invalid document untouched.
- The installer records the override names it writes inside the managed Pi agent directory.
- Both tools merge with perl's core `JSON::PP` module. When perl or the module is unavailable, neither tool modifies `settings.json`: the installer prints the JSON to add, and the uninstaller lists the entries to remove manually.
- The installer and the uninstaller update `settings.json` through a temporary file and a rename, so a failed write leaves the original byte-identical.

## Scenarios

### Scenario: Installer writes the pinned overrides

* *GIVEN* the payload pins a model for an installed agent and the operator's `settings.json` exists
* *WHEN* the installer installs the Pi agents
* *THEN* the installer SHALL set `subagents.agentOverrides.<agent>.model` to the pinned model
* *AND* the installer SHALL preserve every other key and value in the file

### Scenario: Installer creates an absent settings.json

* *GIVEN* the payload pins at least one model and `settings.json` does not exist
* *WHEN* the installer installs the Pi agents
* *THEN* the installer SHALL create `settings.json` with the pinned `subagents.agentOverrides.<agent>.model` entries

### Scenario: Installer writes nothing when no model is pinned

* *GIVEN* the payload pins no Pi model and no previous install recorded overrides
* *WHEN* the installer installs the Pi agents
* *THEN* the installer MUST NOT create or modify `settings.json`

### Scenario: Installer removes overrides the previous install recorded but the current payload no longer pins

* *GIVEN* the previous install recorded override names and the current payload pins none of them
* *WHEN* the installer installs the Pi agents
* *THEN* the installer SHALL remove those entries from `settings.json`
* *AND* the installer SHALL rewrite the marker to the current set of pinned names
* *AND* the installer MUST NOT modify any other key

### Scenario: Repeated installs are idempotent

* *GIVEN* the pinned overrides are installed
* *WHEN* the installer runs again
* *THEN* `settings.json` SHALL remain byte-identical

### Scenario: Uninstall removes only the entries it wrote

* *GIVEN* the installer recorded the override names it wrote
* *WHEN* the uninstaller removes the Pi agents
* *THEN* the uninstaller SHALL remove those override entries
* *AND* the uninstaller MUST NOT remove entries for other agents or any unrelated key

### Scenario: Uninstaller does nothing when settings.json is absent

* *GIVEN* the installer recorded override names and `settings.json` does not exist
* *WHEN* the uninstaller removes the Pi agents
* *THEN* the uninstaller SHALL remove nothing and MUST NOT create the file

### Scenario: Installer leaves an invalid settings.json untouched

* *GIVEN* `settings.json` exists and is not a valid JSON document
* *WHEN* the installer installs the Pi agents
* *THEN* the installer SHALL warn and skip the settings update without failing the install
* *AND* the installer MUST NOT modify the file

### Scenario: Uninstaller leaves an invalid settings.json untouched

* *GIVEN* `settings.json` exists and is not a valid JSON document
* *WHEN* the uninstaller removes the Pi agents
* *THEN* the uninstaller SHALL warn and skip the settings update without failing the uninstall
* *AND* the uninstaller MUST NOT modify the file

### Scenario: A failed write leaves the original settings.json byte-identical

* *GIVEN* `settings.json` exists
* *WHEN* the installer or the uninstaller updates it and the write fails
* *THEN* the update SHALL go through a temporary file and a rename
* *AND* the original file SHALL remain byte-identical

### Scenario: Installer degrades without a JSON writer

* *GIVEN* perl or its JSON module is unavailable
* *WHEN* the installer installs the Pi agents
* *THEN* the installer SHALL warn and print the override JSON for manual use
* *AND* the installer MUST NOT write or partially modify `settings.json`

### Scenario: Uninstaller degrades without a JSON writer

* *GIVEN* perl or its JSON module is unavailable
* *WHEN* the uninstaller removes the Pi agents
* *THEN* the uninstaller SHALL warn and list the `subagents.agentOverrides` entries to remove manually
* *AND* the uninstaller SHALL exit 0 without modifying `settings.json`
