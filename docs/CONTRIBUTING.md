# Contributing

Setup, code style, and testing for clash.

## Prerequisites

- **Godot 4.6+** (any build — clash uses GDScript per ADR 0020, so the .NET / mono build is not required). On Windows the standard build is fine; use the `_console.exe` variant when running from CLI to capture stdout/stderr.
- **gdtoolkit** for `gdlint` and `gdformat`: `pip install gdtoolkit`.
- (M2+, if proto is chosen as the wire format) **godobuf** as a per-project addon for `.proto` → GDScript codegen: see [github.com/oniksan/godobuf](https://github.com/oniksan/godobuf).

## Cloning the repo (fresh setup)

The Godot project (`client/project.godot`) is already committed. For a fresh clone:

1. **Install the external godot-ai-plugin addon when you have access to it.**
   The currently committed Godot settings reference its editor plugin and
   `AiGameBridge` autoload, so linking it avoids missing-addon warnings even
   though gameplay and the automated tests do not depend on the bridge. Either:
   - Junction the source repo into `client/addons/godot_ai/` (Windows; junction stays gitignored):
     ```powershell
     New-Item -ItemType Junction `
       -Path "client\addons\godot_ai" `
       -Target "<absolute path to godot-ai-plugin>\addons\godot_ai"
     ```
   - Or copy/symlink the addon source into `client/addons/godot_ai/` by your platform's preferred mechanism.
2. **Open Godot 4.6+** (any build — clash is GDScript per ADR 0020), open `client/`. The plugin should activate automatically because it's already listed in `[editor_plugins]` in `project.godot`.
3. (Optional) Wire the godot-ai-plugin MCP server into your agent tooling.

   ```powershell
   claude mcp add --scope user --transport stdio godot node "<plugin>\mcp-server\dist\godot-mcp.js"
   ```

The plugin is development tooling, not a shipped game dependency. If you do
not have it, the headless suite still runs but Godot currently logs expected
missing-plugin and missing-autoload diagnostics, including `ERROR` lines. Judge
the run by each test summary and the final process exit status. You may disable
the editor plugin and remove the
missing autoload locally; do not commit that `project.godot` diff. Restoring
the file before committing keeps the shared development configuration intact.

## First time project bootstrap (already done)

The initial bootstrap was performed once via the Godot editor:

1. New Project at `client/`, name `Clash`, renderer `Compatibility`.
2. Plugin enabled in Project Settings → Plugins.

Documented for posterity. Future contributors don't run this step — they use the "Cloning the repo" steps above.

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
