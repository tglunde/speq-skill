[speq-skill](../README.md) / [Docs](./index.md) / Model Routing

---

# Model Routing

speq-skill routes work between a main session, workflow skills, and specialist sub-agents.

---

## Principle

> Orchestration is cheap. Reasoning is expensive.

Workflow skills coordinate the work. They gather context, ask clarifying questions, confirm preconditions, and dispatch specialist roles. Planning, expert implementation, and review use the heavier reasoning tier. An error in these steps compounds in later steps.

---

## Routing table

`model-routing.yml` at the repository root is the single source for every model, effort, and thinking value. The three tables below are generated from it. Edit the table, then run:

```bash
./scripts/plugin/render-model-routing-docs.sh
```

The repository-tree copies under `.claude/` carry no routing and inherit the session model. The plugin build injects the table's values into each emitted plugin tree.

---

## Claude routing

<!-- BEGIN GENERATED claude routing table -->
| Skill or agent | Model | Effort | Notes |
|----------------|-------|--------|-------|
| `/speq:plan` | `sonnet` | inherited | Thin orchestration |
| `/speq:implement` | `sonnet` | inherited | Thin orchestration |
| `/speq:record` | `sonnet` | inherited | Thin orchestration |
| `/speq:mission` | inherited | inherited | Interactive bootstrap |
| `/speq:plan-pr` | `sonnet` | inherited | Thin orchestration (headless) |
| `/speq:implement-pr` | `sonnet` | inherited | Thin orchestration (headless) |
| `/speq:audit` | `sonnet` | inherited | Thin orchestration (health check) |
| `/speq:adr-rules` | inherited | inherited | Reference material for the caller |
| `/speq:cli` | inherited | inherited | Reference material for the caller |
| `/speq:code-guardrails` | inherited | inherited | Reference material for the caller |
| `/speq:code-review` | inherited | inherited | Reference material for the caller |
| `/speq:code-tools` | inherited | inherited | Reference material for the caller |
| `/speq:design-philosophy` | inherited | inherited | Reference material for the caller |
| `/speq:ext-research` | inherited | inherited | Reference material for the caller |
| `/speq:git-discipline` | inherited | inherited | Reference material for the caller |
| `/speq:git-operations` | inherited | inherited | Reference material for the caller |
| `/speq:plan-review` | inherited | inherited | Reference material for the caller |
| `/speq:planning` | inherited | inherited | Reference material for the caller |
| `/speq:spec-merge` | inherited | inherited | Reference material for the caller |
| `/speq:writing-guardrails` | inherited | inherited | Reference material for the caller |
| `planner-agent` | `opus` | `xhigh` | Spec deltas, context, task decomposition |
| `plan-reviewer` | `opus` | `xhigh` | Adversarial plan review |
| `implementer-agent` | `sonnet` | `high` | Standard implementation tasks |
| `implementer-expert-agent` | `opus` | `xhigh` | Tasks tagged `[expert]` |
| `code-reviewer` | `opus` | `xhigh` | Adversarial implementation review |
| `audit-agent` | `opus` | `high` | Mission ↔ spec-library sync |
| `architecture-agent` | `opus` | `high` | Brownfield draft of `specs/architecture.md` for `/speq:mission` |
| `adr-audit-agent` | `fable` | `high` | ADR noise and accuracy review |
| `recorder-agent` | `sonnet` | `medium` | Deterministic spec merge and archive |
<!-- END GENERATED claude routing table -->

---

## Codex routing

<!-- BEGIN GENERATED codex routing table -->
| Skill or agent | Model | Effort | Notes |
|----------------|-------|--------|-------|
| `/speq:plan` | `gpt-5.4` | `medium` | Thin orchestration |
| `/speq:implement` | `gpt-5.4` | `medium` | Thin orchestration |
| `/speq:record` | `gpt-5.4` | `medium` | Thin orchestration |
| `/speq:mission` | inherited | inherited | Interactive bootstrap |
| `/speq:plan-pr` | `gpt-5.4` | `medium` | Thin orchestration (headless) |
| `/speq:implement-pr` | `gpt-5.4` | `medium` | Thin orchestration (headless) |
| `/speq:audit` | `gpt-5.4` | `medium` | Thin orchestration (health check) |
| `/speq:adr-rules` | inherited | inherited | Reference material for the caller |
| `/speq:cli` | inherited | inherited | Reference material for the caller |
| `/speq:code-guardrails` | inherited | inherited | Reference material for the caller |
| `/speq:code-review` | inherited | inherited | Reference material for the caller |
| `/speq:code-tools` | inherited | inherited | Reference material for the caller |
| `/speq:design-philosophy` | inherited | inherited | Reference material for the caller |
| `/speq:ext-research` | inherited | inherited | Reference material for the caller |
| `/speq:git-discipline` | inherited | inherited | Reference material for the caller |
| `/speq:git-operations` | inherited | inherited | Reference material for the caller |
| `/speq:plan-review` | inherited | inherited | Reference material for the caller |
| `/speq:planning` | inherited | inherited | Reference material for the caller |
| `/speq:spec-merge` | inherited | inherited | Reference material for the caller |
| `/speq:writing-guardrails` | inherited | inherited | Reference material for the caller |
| `planner-agent` | `gpt-5.5` | `xhigh` | Spec deltas, context, task decomposition |
| `plan-reviewer` | `gpt-5.5` | `xhigh` | Adversarial plan review |
| `implementer-agent` | `gpt-5.4` | `high` | Standard implementation tasks |
| `implementer-expert-agent` | `gpt-5.5` | `xhigh` | Tasks tagged `[expert]` |
| `code-reviewer` | `gpt-5.5` | `xhigh` | Adversarial implementation review |
| `audit-agent` | `gpt-5.5` | `high` | Mission ↔ spec-library sync |
| `architecture-agent` | `gpt-5.5` | `high` | Brownfield draft of `specs/architecture.md` for `/speq:mission` |
| `adr-audit-agent` | `gpt-5.5` | `high` | ADR noise and accuracy review |
| `recorder-agent` | `gpt-5.4` | `medium` | Deterministic spec merge and archive |
<!-- END GENERATED codex routing table -->

---

## Pi routing

Pi skill frontmatter carries no model or reasoning level, so the orchestration skills run on the session model. The sub-agents carry a reasoning level and no model: a Pi model id names a provider, and pinning one in frontmatter would mandate a vendor.

The build emits `pi/model-overrides.json` from the non-null `pi.model` values in the table. The installer reads it and writes `subagents.agentOverrides.<name>.model` into `~/.pi/agent/settings.json`, recording the names it wrote so it can remove exactly those entries on reinstall or uninstall. The table pins a model for all nine agents, so a fresh install writes nine overrides. The installer writes a provider-qualified pin only when the operator has that provider configured, and warns instead when it skips one. A bare model id names no provider and is written unchanged.

<!-- BEGIN GENERATED pi routing table -->
| Skill or agent | Model | Thinking | Notes |
|----------------|-------|----------|-------|
| `/skill:speq-plan` | inherited | inherited | Thin orchestration |
| `/skill:speq-implement` | inherited | inherited | Thin orchestration |
| `/skill:speq-record` | inherited | inherited | Thin orchestration |
| `/skill:speq-mission` | inherited | inherited | Interactive bootstrap |
| `/skill:speq-plan-pr` | inherited | inherited | Thin orchestration (headless) |
| `/skill:speq-implement-pr` | inherited | inherited | Thin orchestration (headless) |
| `/skill:speq-audit` | inherited | inherited | Thin orchestration (health check) |
| `/skill:speq-adr-rules` | inherited | inherited | Reference material for the caller |
| `/skill:speq-cli` | inherited | inherited | Reference material for the caller |
| `/skill:speq-code-guardrails` | inherited | inherited | Reference material for the caller |
| `/skill:speq-code-review` | inherited | inherited | Reference material for the caller |
| `/skill:speq-code-tools` | inherited | inherited | Reference material for the caller |
| `/skill:speq-design-philosophy` | inherited | inherited | Reference material for the caller |
| `/skill:speq-ext-research` | inherited | inherited | Reference material for the caller |
| `/skill:speq-git-discipline` | inherited | inherited | Reference material for the caller |
| `/skill:speq-git-operations` | inherited | inherited | Reference material for the caller |
| `/skill:speq-plan-review` | inherited | inherited | Reference material for the caller |
| `/skill:speq-planning` | inherited | inherited | Reference material for the caller |
| `/skill:speq-spec-merge` | inherited | inherited | Reference material for the caller |
| `/skill:speq-writing-guardrails` | inherited | inherited | Reference material for the caller |
| `speq-planner-agent` | `opencode/qwen3.8-max` | `xhigh` | Spec deltas, context, task decomposition |
| `speq-plan-reviewer` | `openrouter/meta/muse-spark-1.3` | `xhigh` | Adversarial plan review |
| `speq-implementer-agent` | `opencode/gpt-5.6-luna` | `high` | Standard implementation tasks |
| `speq-implementer-expert-agent` | `opencode/qwen3.8-max` | `xhigh` | Tasks tagged `[expert]` |
| `speq-code-reviewer` | `openrouter/meta/muse-spark-1.3` | `xhigh` | Adversarial implementation review |
| `speq-audit-agent` | `opencode/glm-5.3-flash` | `high` | Mission ↔ spec-library sync |
| `speq-architecture-agent` | `opencode/gemini-3.1-pro` | `high` | Brownfield draft of `specs/architecture.md` for `/speq:mission` |
| `speq-adr-audit-agent` | `opencode/glm-5.3-flash` | `high` | ADR noise and accuracy review |
| `speq-recorder-agent` | `opencode/gpt-5.6-luna` | `medium` | Deterministic spec merge and archive |
<!-- END GENERATED pi routing table -->

### Pin the Pi models

A non-null `pi.model` in a routing row is the way to pin a model. Edit the row in `model-routing.yml`, set `pi.model` to a model id your providers expose, rebuild the plugin with `./scripts/plugin/build.sh`, and reinstall. The installer reconciles `~/.pi/agent/settings.json`: it writes an override for every pinned row whose provider the operator has configured, and removes the entries its previous install recorded.

To override a model by hand, outside the installer's control, edit `~/.pi/agent/settings.json` directly:

```json
{
  "subagents": {
    "agentOverrides": {
      "speq-planner-agent": { "model": "<provider>/<heavy-model>" },
      "speq-plan-reviewer": { "model": "<provider>/<heavy-model>" },
      "speq-implementer-expert-agent": { "model": "<provider>/<heavy-model>" },
      "speq-code-reviewer": { "model": "<provider>/<heavy-model>" }
    }
  }
}
```

The installer removes only the entries it recorded, so a manual entry survives a reinstall or uninstall. An override replaces only the fields it sets, so the thinking levels above still apply.

---

## Expert task tagging

`planner-agent` marks tasks that need deep reasoning with the tag `[expert]`:

```markdown
- [ ] 2.1 Add CLI flag parsing
- [ ] 2.2 Implement lock-free queue for concurrent spec writes [expert]
```

When `/speq:implement` processes a task group:

- Untagged tasks route to `implementer-agent`
- `[expert]` tasks route to `implementer-expert-agent`
- When expert tasks establish invariants that standard tasks depend on, they run first

Use `[expert]` for concurrency, subtle correctness, cross-file refactors, novel algorithms, and security-sensitive work. Avoid it for routine CLI plumbing, fixtures, docs, or straightforward use of existing patterns.

On Pi the same agents carry the `speq-` prefix, so the routes are `speq-implementer-agent` and `speq-implementer-expert-agent`.
