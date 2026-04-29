# Contributing

Setup, code style, and testing for clash.

## Prerequisites

- **Godot 4.6+** (any build — clash uses GDScript per ADR 0020, so the .NET / mono build is not required). On Windows the standard build is fine; use the `_console.exe` variant when running from CLI to capture stdout/stderr.
- **gdtoolkit** for `gdlint` and `gdformat`: `pip install gdtoolkit`.
- (M2+, if proto is chosen as the wire format) **godobuf** as a per-project addon for `.proto` → GDScript codegen: see [github.com/oniksan/godobuf](https://github.com/oniksan/godobuf).

## First time project setup

The Godot project lives in `client/`. To create it the first time:

1. Open Godot.
2. New Project, browse to `<repo>/client/`. **Project Name:** `Clash`. **Renderer:** `Compatibility` (best for HTML5 / mobile export). Leave **Version Control Metadata** blank — repo-level git already exists.
3. **Create & Edit**. Do NOT use the "Create C# Solution" tool — clash is GDScript per ADR 0020.
4. The repo's `.gitignore` already covers `.godot/`, `.import/`, etc.

For day-to-day work, open the `client/` folder in Godot.

## Running Godot from CLI (Windows)

See [docs/GODOT-NOTES.md](GODOT-NOTES.md) for the Windows console launch command and `@tool` script gotchas.

## Code style

| Stack | Style | Tooling |
|-------|-------|---------|
| GDScript | snake_case, gdtoolkit defaults, prefer strict typing | `gdformat`, `gdlint` (config in `gdlintrc`) |
| Server (TBD at M2) | Picked then | Picked then |
| Proto (if chosen at M2) | buf style guide for the `.proto` files | `buf format`, `buf lint` |

## Testing

- **GDScript:** Use Godot's built-in test runner, GUT (Godot Unit Test), or `@tool`-driven test scenes; gdtoolkit doesn't include a runner.
- **Server:** Test framework picked at M2 alongside the server stack.

## Pre commit gate

`scripts/precommit-clash.sh` (run as a Claude Code hook on `git commit`) runs only the checks relevant to staged files:

- Staged `*.gd` → `gdlint`, `gdformat --check` on the staged files.
- Staged `*.proto` → `buf lint`, `buf format --diff --exit-code`, plus codegen no-drift check (only once proto is wired up at M2).
- Server-side checks added when the server lands at M2.

Override with `git commit --no-verify` only if you understand why.

## Format on save

`scripts/format-on-save.sh` (PostToolUse hook) auto formats edited files based on extension. No manual action required.
