# Feature: Pi Model Overrides

The installer pins the routing table's Pi models for the installed sub-agents through Pi settings overrides, and the uninstaller removes exactly those entries.

<!-- DELTA:CHANGED -->
## Background

- Pi resolves a sub-agent's model from `subagents.agentOverrides.<name>.model` in `~/.pi/agent/settings.json` before the agent's frontmatter.
- The plugin build emits the pinned models as `pi/model-overrides.json` in the Pi payload. An empty object means no agent is pinned.
- `settings.json` belongs to the operator and can hold unrelated keys. It may be absent or hold an invalid document.
- The installer creates `settings.json` only when it pins at least one model; both tools warn and leave an invalid document untouched.
- The installer records the override names it writes inside the managed Pi agent directory.
- Both tools merge with perl's core `JSON::PP` module. When perl or the module is unavailable, neither tool modifies `settings.json`: the installer prints the JSON to add, and the uninstaller lists the entries to remove manually.
- The installer and the uninstaller update `settings.json` through a temporary file and a rename, so a failed write leaves the original byte-identical.
- Each installer invocation SHALL read the Pi agent files and `pi/model-overrides.json` from the same `MARKETPLACE_DIR`.
- The caller MAY provide `MARKETPLACE_DIR`; when it is absent, the installer and uninstaller use `$HOME/.speq-skill`.
- Before removing an existing marketplace directory, the uninstaller MUST reject `/`, exactly `$HOME`, and any `MARKETPLACE_DIR` without `.claude-plugin/marketplace.json`, exit non-zero, and name the rejected directory. When `MARKETPLACE_DIR` does not exist, the uninstaller MUST warn and name the directory, skip only marketplace removal, continue the remaining uninstall steps, and exit 0. A valid installed marketplace root contains that marker.
<!-- /DELTA:CHANGED -->

## Scenarios

<!-- DELTA:NEW -->
### Scenario: Installer uses one payload root for Pi agents and overrides

* *GIVEN* the caller's `MARKETPLACE_DIR` contains Pi agent files and a `pi/model-overrides.json` pin for an agent
* *AND* another payload root contains a different pin for that same agent
* *WHEN* the installer installs the Pi agents using the caller's `MARKETPLACE_DIR`
* *THEN* the installer SHALL copy the agent file from the caller's payload root
* *AND* the installer SHALL write the pin from the caller's `pi/model-overrides.json` to `settings.json`
* *AND* the installer MUST NOT write the pin from the other payload root
<!-- /DELTA:NEW -->

<!-- DELTA:NEW -->
### Scenario: Uninstaller honors a caller-provided marketplace directory

* *GIVEN* two marketplace directories exist
* *AND* the caller sets `MARKETPLACE_DIR` to one of them
* *WHEN* the uninstaller removes the installation
* *THEN* the uninstaller SHALL remove the marketplace directory named by `MARKETPLACE_DIR`
* *AND* the uninstaller MUST NOT remove the other marketplace directory
<!-- /DELTA:NEW -->

<!-- DELTA:NEW -->
### Scenario: Uninstaller skips an absent marketplace directory

* *GIVEN* `MARKETPLACE_DIR` names a path that does not exist
* *WHEN* the uninstaller runs
* *THEN* the uninstaller SHALL warn and name the absent directory
* *AND* the uninstaller SHALL skip only the marketplace-removal step
* *AND* the uninstaller SHALL continue the remaining uninstall steps
* *AND* the uninstaller SHALL exit with status 0
<!-- /DELTA:NEW -->

<!-- DELTA:NEW -->
### Scenario: Uninstaller guards marketplace removal targets

* *GIVEN* unsafe marketplace targets are `/`, exactly `$HOME`, and an existing directory without `.claude-plugin/marketplace.json`
* *AND* a separate valid marketplace target contains `.claude-plugin/marketplace.json`
* *WHEN* the uninstaller runs separately with `MARKETPLACE_DIR` set to each unsafe target
* *THEN* each invocation SHALL exit non-zero before removing any path
* *AND* each invocation SHALL name its rejected directory in its message
* *AND* each unsafe target MUST remain intact
* *WHEN* the uninstaller runs with `MARKETPLACE_DIR` set to the valid target
* *THEN* the uninstaller SHALL complete successfully and remove the valid marketplace target
<!-- /DELTA:NEW -->
