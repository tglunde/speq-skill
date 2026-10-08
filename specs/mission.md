# Mission: speq-skill

> A spec-driven development system for AI coding agents: a CLI plus a set of skills that plan, implement, and record features against a permanent spec library.

## Problem Statement

AI coding agents work more effectively with structured, consistent specifications. Without tooling, feature specs:
- Lack structural consistency (missing sections, malformed scenarios)
- Cannot be verified programmatically
- Are difficult to discover and navigate across large codebases

speq provides structural verification and exploration tools so AI agents can reliably read and update specs that follow a predictable format.

## Target Users

| Persona | Goal | Key Workflow |
|---------|------|--------------|
| AI coding agent | Read/write consistent specs during development | Plan → Implement → Record: create delta specs, implement features, record to permanent specs |
| Developer | Investigate and maintain specs | List specs, validate structure, review changes |

## Core Capabilities

1. **Retrieve spec content**: Fetch a full feature spec or a single scenario by path (`speq feature get <domain>/<feature>[/<scenario>]`)
2. **List features and domains**: Display specs in a tree view organized by domain, or list domains alone (`speq domain list`)
3. **Validate spec structure**: Check specs for required sections (Feature, Background, Scenarios), RFC2119 keyword usage, and scenario format
4. **Search specs**: Semantic search over scenarios using pure-Rust ONNX inference (tract-onnx) with a locally cached embedding model; no external runtime required
5. **Inspect plans in flight**: List active plans under `_plans/` and validate a plan's delta specs before recording (`speq plan list` / `speq plan validate <plan>`)
6. **Record plan deltas**: Merge approved delta specs from `_plans/` into permanent specs and archive the plan
7. **Track architecture decisions**: Validate and assemble per-plan ADR fragments in `specs/_decision/` into a stable decision record (`speq decision-log validate` / `show`)
8. **Bootstrap a project**: Interview the user about purpose and architecture, then write `specs/mission.md` and `specs/architecture.md`; for an existing codebase, draft the architecture from the code first (`/speq:mission`)
9. **Plan a change**: Interview the user and write spec deltas, `plan.md`, and `decision-log.md` under `specs/_plans/<plan-name>/`, with a reviewer agent challenging the plan before implementation (`/speq:plan`)
10. **Implement a plan**: Split the plan into tasks, hand them to TDD sub-agents, review the resulting code, run the build, tests, and lint checks, and write `verification-report.md` (`/speq:implement`)
11. **Record an implemented plan**: Merge the spec deltas and any architecture delta, accept the proposed ADRs, and archive the plan under `specs/_recorded/` (`/speq:record`)
12. **Audit the library**: Check structure, ADRs, mission drift, and unrecorded plans, then offer a gated fix for each finding (`/speq:audit`)
13. **Run the cycle headless on a pull request**: Plan and implement without a live interview, commit to a `feat/<plan-name>` branch, and open or update a pull request (`/speq:plan-pr`, `/speq:implement-pr`)
14. **Distribute the plugin and the installer**: Build Claude Code and Codex plugin trees from the shared skill source, and install the CLI, the embedding model, the skills, and MCP registration (`scripts/plugin/build.sh`, `install.sh`)

## Out of Scope

- Execution engine: Does not run or execute specifications like a test runner
- Language or framework support: The CLI and the skills stay language-agnostic
- Unplanned code generation: Every change is planned and reviewed before it is implemented
- Model routing: Does not mandate a model or a vendor
- Spec history: Does not manage it beyond archiving recorded plans

Architecture: see specs/architecture.md.

## Domain Glossary

| Term | Definition |
|------|------------|
| Spec | A feature specification file (`spec.md`) written in Gherkin-like Markdown |
| Domain | A grouping of related features (e.g., `cli/`, `validation/`) |
| Feature | A single capability defined with Background and Scenarios sections |
| Scenario | A specific behavior described with GIVEN/WHEN/THEN steps |
| Delta | A proposed change to a spec marked with `<!-- DELTA:NEW -->`, `<!-- DELTA:CHANGED -->`, or `<!-- DELTA:REMOVED -->`, targeting a `### Scenario:`, or realigning an existing feature's `## Background` or `# Feature: <name>` description to match a scenario change |
| Plan | A set of deltas in `_plans/<plan-name>/` awaiting approval |
| Record | The action of moving approved deltas from `_plans/` to permanent specs in `specs/` |
| ADR | An Architecture Decision Record — a single durable decision captured as a slug-identified fragment in `specs/_decision/`. It is not the design section of a plan |

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Language | Rust (edition 2024) | Performance, reliability, single binary distribution |
| CLI | clap 4.5 | Command-line argument parsing with derive macros |
| Parsing | pulldown-cmark 0.13 | Markdown parsing for spec analysis |
| Inference | tract-onnx | Pure-Rust ONNX inference for semantic search (no native runtime required) |
| Tokenization | tokenizers | Fast tokenization for embedding inputs |
| Errors | thiserror 2 | Ergonomic error type definitions |
| Serialization | serde | Serialize embedding-index and metadata structures |
| Serialization | postcard | Compact binary format for the cached embedding index |
| Platform paths | dirs | Resolve the platform cache directory for the embedding model and index |
| Parallelism | rayon | Parallel iteration for search indexing and query |
| Skills | Markdown `SKILL.md` files under `.claude/skills/` | Define each workflow step, its guardrails, and its sub-agent contract |
| Sub-agents | Markdown agent definitions under `.claude/agents/` | Assign specialist roles for planning, review, implementation, and recording |
| Plugin packaging | Bash (`scripts/plugin/build.sh`) | Compile the shared skill source into Claude Code and Codex plugin trees |
| Installer | Bash (`install.sh`) | Install the binary, the embedding model, the skills, and MCP registration |
| Testing | assert_cmd, predicates, tempfile | CLI integration testing |
| Testing | serial_test | Serialize tests that share process-global state (e.g. the cache directory) |

## Commands

```bash
# Build
cargo build --release

# Test
cargo test

# Lint & Format
cargo fmt && cargo clippy

# Gather Code Coverage
cargo llvm-cov

# Build the plugin
./scripts/plugin/build.sh

# Build a release artifact
./scripts/release/build.sh <vX.Y.Z>

# Test a release artifact
./scripts/release/test.sh <vX.Y.Z>
```

## Project Structure

```
speq-skill/
├── .claude/              # Skill and sub-agent source, compiled into the plugin
│   ├── agents/           # Sub-agent definitions
│   └── skills/           # Workflow, guardrail, and utility skills
├── docs/                 # User documentation
├── scripts/              # Plugin, release, and local-install scripts
├── src/                  # Rust source for the `speq` CLI
├── specs/                # Feature specifications
│   ├── <domain>/         # Domain grouping
│   │   └── <feature>/    # Feature directory
│   │       └── spec.md   # Specification file
│   ├── _plans/           # Pending plan deltas
│   ├── _recorded/        # Archived recorded plans
│   └── _decision/        # Architecture Decision Record fragments
├── tests/                # Integration tests
├── dist/                 # Generated plugin and release artifacts (gitignored)
├── install.sh            # Installer
└── uninstall.sh          # Uninstaller
```

## Constraints

- **Spec format stability**: Spec structure must remain backward compatible to avoid breaking existing specs
