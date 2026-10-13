# Project Hook Loading

Shared by every entry-point orchestrator: `speq-mission`, `speq-plan`, `speq-plan-pr`, `speq-implement`, `speq-implement-pr`, `speq-record`, and `speq-audit`. A project adds `.speq/<name>-hook.md` to extend or override that orchestrator's workflow for one repository. `docs/hooks.md` is the human-facing reference.

## Procedure

1. Read `.speq/<name>-hook.md` if it exists.
2. If present, announce `Loaded project hook: .speq/<name>-hook.md`.
3. Treat the hook content as authoritative. It can add to, change, or override any part of the workflow. When the hook conflicts with the workflow, the hook wins.
4. If absent, continue without mention.
5. When the orchestrator spawns sub-agents, pass the hook path (not its content) as a `Project Hook:` line in each brief. A sub-agent reads the file itself when the file bears on its task.
