# Decisions: add-model-routing-table

## ADR: One routing table owns per-harness model and effort

**ID:** one-routing-table-owns-model-and-effort
**Plan:** add-model-routing-table
**Status:** Accepted

### Context

Agent and skill model, effort, and thinking values appear in the source frontmatter and in the plugin build scripts, so one routing change touches several places and drifts when one is missed.

### Decision

Every agent and skill takes its model, effort, and thinking values from one routing table. The source frontmatter carries none of them. The build injects the values into each emitted tree, and the installer propagates the Pi model ids into the operator's Pi settings.

### Options Considered

| Option | Verdict |
|--------|---------|
| One routing table as the single owner | ✓ Chosen: one edit point and one validation point for every harness |
| Keep the values in the source frontmatter and transform them per harness | ✗ Rejected: each change touches several files and drifts |
| Parse the table with a YAML library | ✗ Rejected: adds a build dependency to a build that stays bash and awk |

### Consequences

- One edit point per routing value.
- Adding an agent or skill requires a table row.
- Pi rows pin no model, so the mission's stance that the plugin mandates no model or vendor still holds.
