# Contributing

Setup, code style, and testing for clash.

## Prerequisites

- **Godot 4.6+** with .NET / mono build. On Windows: `Godot_v4.6.1-stable_mono_win64.exe` (use `_console.exe` when running from CLI to capture stdout/stderr).
- **.NET 8 SDK** (for C#).
- **Go 1.22+** (when working on `server/`).
- **gdtoolkit** for `gdlint` and `gdformat`: `pip install gdtoolkit`.
- **buf** for protobuf: see [buf install docs](https://buf.build/docs/installation).

## First time project setup

The Godot project lives in `client/`. To create it the first time:

1. Open Godot.
2. New Project, browse to `<repo>/client/`, language: C# (.NET).
3. Save. This creates `project.godot`, `Clash.csproj`, `Clash.sln` inside `client/`.
4. The repo's `.gitignore` already covers `.godot/`, `bin/`, `obj/`, etc.

For day to day work, open the `client/` folder in Godot.

## Running Godot from CLI (Windows)

See [docs/GODOT-NOTES.md](GODOT-NOTES.md) for the Windows console launch command and `@tool` script gotchas.

## Code style

| Stack | Style | Tooling |
|-------|-------|---------|
| C# | Standard .NET conventions, opening brace same line | `dotnet format` |
| GDScript | snake_case, gdtoolkit defaults | `gdformat`, `gdlint` (config in `gdlintrc`) |
| Go | Standard Go conventions | `golangci-lint` (config in `.golangci.yml`, added when first Go file lands) |
| Proto | buf style guide | `buf format`, `buf lint` |

## Testing

- **C#:** `dotnet test` from `client/`.
- **GDScript:** Use Godot's built in test runner or `@tool` driven test scenes; gdtoolkit doesn't include a runner.
- **Go:** `go test -race ./...` from `server/`.

## Pre commit gate

`scripts/precommit-clash.sh` (run as a Claude Code hook on `git commit`) runs only the checks relevant to staged files:

- Staged `*.cs` → `dotnet format --verify-no-changes`, `dotnet build`, `dotnet test` from `client/`.
- Staged `*.gd` → `gdlint`, `gdformat --check` on the staged files.
- Staged `*.go` → `go vet`, `go test -race ./...` from `server/`.
- Staged `*.proto` → `buf lint`, `buf format --diff --exit-code`, plus codegen no drift check.

Override with `git commit --no-verify` only if you understand why.

## Format on save

`scripts/format-on-save.sh` (PostToolUse hook) auto formats edited files based on extension. No manual action required.
