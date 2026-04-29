# clash

Turn based PvP strategy game. Two players queue actions during a shared timer; the server resolves all actions deterministically each turn (attacks before moves, target chains, fallback to closest enemy unless on hold fire). Web and mobile (Godot HTML5 / Android / iOS exports). See @docs/ARCHITECTURE.md for the data flow and @docs/DECISIONS.md for the why.

## Key Principles

1. **Type schemas live in code, not markdown.** At M0 the data layer is hand-written C# Resources per the design spec at `docs/superpowers/specs/2026-04-29-entity-data-model-design.md`. Proto for cross-language wire types is one candidate for M2 alongside others (see ADR 0006); decision deferred until then. Either way, never duplicate type definitions in markdown.
2. **Resolver is server-authoritative once a server exists.** At M0/M1 the resolver lives in the Godot client (driven by dev tooling, then by an AI opponent at M1). At M2 the resolver moves to a server; clients render the resolved outcome and never speculate.
3. **C# default, GDScript when ergonomic.** Game code in C# unless GDScript is meaningfully simpler for a specific node, signal hookup, or `@tool` script.
4. **One repo, three stacks.** Godot in `client/`, Go in `server/`, protobuf in `proto/`. The root `Makefile` orchestrates codegen and checks across stacks.
5. **Test the system before adding complexity.** Most "we need a fallback" intuitions disappear once you reproduce the case.
6. **No backward compatibility.** Single user project pre release. Breaking changes are free; update everything at once and delete the old code.
7. **Never commit or push without explicit instruction.** Verifying and running checks is fine; write operations require the user to ask.

## Architecture

At M0 the resolver lives in the Godot client and is driven by dev tooling — no network, no server, no AI. M1 adds an AI opponent (still all client-side). M2 adds network play; the server technology and wire protocol are picked at that point. Candidate paths (Go + protobuf, headless Godot/C#, Nakama, etc.) are listed in the design spec. See @docs/ARCHITECTURE.md and @docs/superpowers/specs/2026-04-29-entity-data-model-design.md.

## Stack Specific

**C# (`client/`, default game code):**
- Solution and `.csproj` live in `client/`, alongside `project.godot`.
- Namespace `Clash.*`. Generated protobuf lives in `client/generated/`.
- Format with `dotnet format`; build with `dotnet build` from `client/`.

**GDScript (`client/`, only where ergonomic):**
- Single file `@tool` editor scripts, simple node behaviours, signal wiring.
- Lint config in `gdlintrc`. Format with `gdformat`.
- For `@tool` scripts, see @docs/GODOT-NOTES.md before committing; there are silent failure modes.

**Go (`server/`, only if Go is chosen at M2 — see ADR 0006):**
- If Go: module `github.com/Z-a-r-a-k-i/clash/server`. Resolver, matchmaker, WebSocket hub. Tests via `go test -race ./...`. Lint config in `.golangci.yml` added when the first Go file lands.
- If a different server stack is chosen at M2 (headless Godot/C#, Nakama, etc.), this section is rewritten then.

**Proto (`proto/`):**
- Versioned package `clash.v1` (`proto/clash/v1/`). New incompatible shape goes to `clash.v2`.
- Code generation via `buf generate`. Generated code is committed to `client/generated/` (C#) and `server/internal/proto/` (Go).
- Run `make generate` after editing `.proto`; the pre commit gate verifies no drift.

## Git Workflow

- Feature branches and PRs only; never commit directly to `main`.
- No conventional commit prefixes (no `fix:`, `feat:`, etc.). Write natural messages focused on what changed and why.
- No "Generated with Claude" or "Co-Authored-By: Claude" footers anywhere.
- Squash and merge via GitHub's UI or `gh pr merge --squash`.

Lint and test enforcement is automated by `.claude/settings.json` hooks: format on save (`scripts/format-on-save.sh`) plus a scope aware pre commit gate (`scripts/precommit-clash.sh`) that runs only the checks relevant to staged files. The agent does not need to remember to run them.

## Pull Requests

- PR descriptions: Summary bullets + Test plan section.
- Address review comments by fixing in code first, then replying confirming the fix, then resolving the thread.
- Outside diff and pre existing comments still get fixed if the suggestion is good.
- Always resolve all review threads after addressing them.

CodeRabbit comment handling and review loops are owned by the `coderabbit:*` and `cr-fix*` skills; use those instead of restating the workflow here.

## Editor plugin

The agent drives the Godot editor through the `godot-ai-plugin` MCP server when needed. The plugin is installed externally and is not vendored into this repo.

## Documentation Philosophy

Code is the source of truth. Define types and schemas in code (proto); never duplicate them in markdown. Use docs for design rationale, architecture decisions, and how things connect, not for restating field lists or enum values.

## Documentation index

- @docs/ARCHITECTURE.md: system architecture and data flows
- @docs/ROADMAP.md: long-horizon milestones M0–M5
- @docs/PROTOCOL.md: tentative wire-protocol sketch (pending M2 network choice)
- @docs/DECISIONS.md: architecture decision records
- @docs/CONTRIBUTING.md: development setup, code style, testing
- @docs/ORCHESTRATION.md: agent orchestration design
- @docs/PARALLEL-AGENTS.md: parallel agent work model
- @docs/GODOT-NOTES.md: Godot `@tool` pitfalls, C# vs GDScript guidance
- @docs/PLAN-FORMAT.md: plan tree format specification
- @docs/superpowers/specs/2026-04-29-entity-data-model-design.md: entity data model and code organization
- plan/: project plan tree (see plan/AGENTS.md for agent facing rules)
