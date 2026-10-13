# Decision Log: add-dark-mode

## Decisions

### D1: Theme lives on the app shell

- **Decision**: Store the selected theme on the app shell rather than on each note.
- **Alternatives**: A per-note theme; a theme per route.
- **Rationale**: `specs/architecture.md` already places theme selection in the app shell.
- **Consequences**: One theme at a time, which is what the request asked for.
