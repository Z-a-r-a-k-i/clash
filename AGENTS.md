# clash

Turn based PvP strategy game with blind simultaneous submissions. Both players
queue actions, submit, and then the authoritative resolver applies the turn
deterministically (attacks before moves, target chains, and closest-enemy
fallback when a focused target is invalid). The current pre-alpha supports solo
AI, AI simulations, replays, and a trusted same-version WebSocket playtest
server in Godot. A shared turn timer, hold-fire behavior, and web/mobile exports
remain future work. See @docs/ARCHITECTURE.md for the data flow and
@docs/DECISIONS.md for the why.

## Key Principles

1. **Type schemas live in code, not markdown.** At M0 the data layer is hand-written GDScript Resources per the design spec at `plan/m0/00-config-and-tunables.md`. Proto for cross-language wire types is one candidate for M2 alongside others (see ADR 0006); decision deferred until then. Either way, never duplicate type definitions in markdown.
2. **Resolver is server-authoritative in network play.** Local and solo modes run the resolver in-process. The trusted network slice runs the same resolver in a headless Godot server and clients render its authoritative result without speculation. M2 decides whether that becomes the production stack or is ported behind the existing boundary.
3. **GDScript only.** Game code is GDScript per ADR 0020. C# is not used; web/mobile platform support gaps in the .NET build of Godot 4.6 disqualify it.
4. **One repo, layered stacks.** Godot in `client/`, server stack (TBD at M2) in `server/`, protobuf in `proto/`. The root `Makefile` orchestrates checks across stacks.
5. **Test the system before adding complexity.** Most "we need a fallback" intuitions disappear once you reproduce the case.
6. **No backward compatibility.** Single user project pre release. Breaking changes are free; update everything at once and delete the old code.
7. **Never commit or push without explicit instruction.** Verifying and running checks is fine; write operations require the user to ask.

## Architecture

M0 established the deterministic resolver and development play surface. M1
added the shared play-mode controller, main-and-natural 1v1 arena, AI opponent, simulation
harness, and major HUD/readability work. A trusted same-version network slice
also exists ahead of the final M2 infrastructure decision: a headless Godot
server hosts invite-code matches with the resolver authoritative. M2 still
decides whether to harden that path or adopt another production stack and wire
format. Candidate paths (Go + protobuf, headless Godot/GDScript, Nakama, etc.)
are listed in the design spec. See @docs/ARCHITECTURE.md,
@docs/NETWORK-PLAYTEST.md, and @plan/m0/00-config-and-tunables.md.

## Stack Specific

**GDScript (`client/`, all game code):**
- Lives in `client/scripts/` (alongside `project.godot`). Use strict typing (`var foo: int`, function signatures with types).
- Define Resource subclasses with `class_name X extends Resource`; one capability sub-resource per file.
- Lint config in `gdlintrc`. Format with `gdformat`. For `@tool` scripts, see @docs/GODOT-NOTES.md — there are silent failure modes.

**Network/server (`client/scripts/network/` now; `server/` reserved — see ADR 0006):**
- The current trusted playtest server is headless Godot inside `client/`, reusing the resolver, scenario resources, and replay types.
- Production server technology and wire protocol are picked at M2. Candidate paths: harden headless Godot, Go + protobuf, Nakama, or another evidence-backed choice.
- The root `server/` directory remains a placeholder unless M2 chooses a separate stack.

**Proto (`proto/`, conditional on proto being chosen at M2 — see ADR 0007):**
- Versioned by folder: `proto/clash/v1/`. Note that godobuf (the GDScript-side codegen) does not support `package` directives — use a name-prefix convention (e.g. `ClashV1TurnStart`) inside messages if proto is adopted.
- Code generation via `make generate` (will invoke godobuf for the client side, plus whatever the server side needs). Generated code is committed; the pre-commit gate verifies no drift.

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

`client/addons/godot_ai/` is gitignored for local setup. After creating a git worktree for this repo, recreate that addon link in the new worktree before opening Godot.

Windows PowerShell:

```powershell
New-Item -ItemType Junction `
  -Path "<worktree>\client\addons\godot_ai" `
  -Target "<path-to-your-main-godot-ai-plugin-checkout>\addons\godot_ai"
```

Linux / macOS:

```bash
ln -s \
  "<path-to-your-main-godot-ai-plugin-checkout>/addons/godot_ai" \
  "<worktree>/client/addons/godot_ai"
```

Use the same local `godot-ai-plugin` addon target as the main checkout unless the user explicitly asks for a different plugin checkout.

**Junction cleanup safety:** `client/addons/godot_ai` is a link to an external plugin checkout, not disposable worktree content. Never recursively delete, move, clean, or enumerate-and-delete inside this path. On Windows, treat `LinkType = Junction` / `ReparsePoint` as a hard stop: remove only the junction entry itself when explicitly cleaning a worktree, for example `Remove-Item "<worktree>\client\addons\godot_ai"` without `-Recurse`. Do not run commands such as `Get-ChildItem client/addons/godot_ai -Recurse | Remove-Item` or `Remove-Item client/addons/godot_ai\* -Recurse`; those delete files from the shared external `godot-ai-plugin` checkout.

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
- @docs/GODOT-NOTES.md: Godot `@tool` pitfalls, language conventions, mobile/web export notes
- @docs/PLAN-FORMAT.md: plan tree format specification
- @plan/m0/00-config-and-tunables.md: entity data model and code organization
- plan/: project plan tree (see plan/AGENTS.md for agent facing rules)
