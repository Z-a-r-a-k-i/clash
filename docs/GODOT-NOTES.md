# Godot Notes

Quick reference for Godot specific gotchas and conventions on clash.

## Language: GDScript only

clash uses GDScript for all game code per ADR 0020. C# was dropped because of platform support gaps (no web export in 4.6/4.7-beta, mobile experimental). All entity defs, resolver code, runtime state, and presentation are GDScript.

Use strict typing where reasonable: explicit type hints on `var` declarations, function parameter types, and return types. Define Resource subclasses with `class_name X extends Resource` (see the design spec at `docs/superpowers/specs/2026-04-29-entity-data-model-design.md`).

## `@tool` script pitfalls

These are hard won lessons from the godot-ai-plugin work. Violating them causes silent, hard to debug failures.

- **No hot reload with `class_name`.** `@tool` scripts that declare `class_name` do NOT hot reload in Godot 4.6. Kill and restart Godot after code changes; editing while Godot is running has no effect.
- **Script errors silently break functions.** When a SCRIPT ERROR occurs mid function in `@tool` code, the function returns early with a default value (null, empty dict, etc.). The error appears only in Godot's stdout; it does NOT propagate through any RPC return. Callers receive a response that looks valid but has incomplete data.
- **Always guard optional methods.** Use `node.has_method("method_name")` before calling methods that may not exist on all subclasses. Example: `get_configuration_warnings()` doesn't exist on `Node2D` in Godot 4.6.1.
- **`EditorInterface.edit_node()` is not the same as opening a scene.** It only highlights the node in the Inspector panel. To open a scene, use `EditorInterface.open_scene_from_path()`.
- **`open_scene_from_path()` is asynchronous.** The scene is not available on the same frame. If you need to use it immediately, defer or wait one frame.

## Running Godot from CLI (Windows)

```bash
"/c/Program Files/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe" \
  --editor --path "C:/Users/alk/Documents/Developpement/games/clash/client" &
```

The `_console.exe` build prints stdout and stderr (the standard build does not on Windows). Always launch the console build when iterating with an agent that needs to read Godot's output.

## Cleaning up test artifacts

Godot creates `.import/`, `.godot/`, and various `*.tmp` files when running tests. These are gitignored. If you ever see `test_*.tscn`, `test_*.tres`, or `.test_*.tmp` at the repo root, delete them; they are stray test outputs.

## Generated protobuf (if proto is chosen at M2)

If proto becomes the wire format at M2 (per ADR 0007), generated GDScript files land in `client/generated/` via [godobuf](https://github.com/oniksan/godobuf). Do not hand-edit them. They are committed to git so fresh clones can build without running codegen.

godobuf does not support proto `package` directives — message names use a name-prefix convention (e.g. `ClashV1TurnStart`).

## Mobile and web exports

Deferred until v1+. When the time comes:

- HTML5 export: requires HTTPS for WebSocket; Godot's HTML5 export needs cross origin isolation headers for SharedArrayBuffer if used.
- Android: signing config required; do not commit keystores.
- iOS: requires macOS for the export; Apple developer account required for distribution.

Set up export presets in `client/export_presets.cfg` (gitignore the secret bits via `.import/` and signing config).
