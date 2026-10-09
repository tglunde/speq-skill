# Feature: Model Routing

One routing table owns the model and reasoning level of every agent and skill, and the plugin build emits each harness's frontmatter from it.

## Background

- The routing table is a build input. It is not part of any plugin payload.
- The table uses a restricted, line-oriented YAML subset: section headers, row names, plain properties, and one-level inline maps. Any other syntax is an error.
- Each agent row and skill row names its source file, a one-line note, and a map per harness: Claude, Codex, and Pi.
- The build fails before it writes an artifact when the table and the source tree disagree.
- The three payloads are the Claude plugin tree, the Codex plugin tree, and the Pi payload.

## Scenarios

### Scenario: Build emits Claude routing

* *GIVEN* the routing table names a Claude model and effort for an agent and a model without effort for a skill
* *WHEN* the build runs
* *THEN* the Claude agent copy SHALL carry the row's `model:` and `effort:` lines
* *AND* the Claude agent copy SHALL keep its `color:` line
* *AND* the Claude skill copy SHALL carry the row's `model:` line and SHALL NOT carry an `effort:` line

### Scenario: Build emits Codex routing

* *GIVEN* the routing table names a Codex model and effort for an agent and a skill
* *WHEN* the build runs
* *THEN* the Codex agent copy SHALL carry the row's `model:` and `effort:` lines
* *AND* the Codex agent copy SHALL keep its `color:` line
* *AND* the Codex skill copy SHALL carry the row's `model:` and `effort:` lines

### Scenario: Build emits Pi reasoning without a model

* *GIVEN* the routing table names a Pi thinking level and a null Pi model for an agent
* *WHEN* the build runs
* *THEN* the Pi agent copy SHALL carry a `thinking:` line with the row's level
* *AND* the Pi agent copy MUST NOT carry `model:`, `effort:`, or `color:`
* *AND* the Pi skill copy MUST NOT carry `model:`, `effort:`, or `thinking:`

### Scenario: Empty harness map inherits the harness default

* *GIVEN* a routing row whose harness map is empty
* *WHEN* the build runs
* *THEN* the emitted copy SHALL carry no `model:`, `effort:`, or `thinking:` line for that harness
* *AND* the documentation renderer SHALL render that row's value as `inherited`

### Scenario: Build rejects syntax outside the subset

* *GIVEN* the routing table contains a line outside the restricted subset
* *WHEN* the build runs
* *THEN* the build SHALL fail with the file, the line number, and the offending line
* *AND* the build MUST NOT write any plugin artifact

### Scenario: Build rejects a source file with no row

* *GIVEN* an agent file or a skill directory has no routing row
* *WHEN* the build runs
* *THEN* the build SHALL fail naming the source file

### Scenario: Build rejects a row with no matching file

* *GIVEN* a routing row names a file that does not exist or does not match the row name
* *WHEN* the build runs
* *THEN* the build SHALL fail naming the row and the expected path

### Scenario: Build rejects routing values in source frontmatter

* *GIVEN* a source agent or skill still carries `model:`, `effort:`, or `thinking:`
* *WHEN* the build runs
* *THEN* the build SHALL fail naming the file and the line

### Scenario: Build writes the Pi model overrides artifact

* *GIVEN* a routing row names a Pi model
* *WHEN* the build runs
* *THEN* the Pi payload SHALL contain a `model-overrides.json` mapping the installed agent name to that model
* *AND* rows with a null Pi model SHALL be absent from the mapping
* *AND* no payload directory SHALL contain the routing table

### Scenario: Documentation matches the routing table

* *GIVEN* the routing table and the committed documentation
* *WHEN* the documentation check runs
* *THEN* the check SHALL pass while the tables match the routing table
* *AND* the check SHALL fail when the committed document is stale
