# Godot Notes

Quick reference for Godot specific gotchas and conventions on clash.

## Language: GDScript only

clash uses GDScript for all game code per ADR 0020. C# was dropped because of platform support gaps (no web export in 4.6/4.7-beta, mobile experimental). All entity defs, resolver code, runtime state, and presentation are GDScript.

Use strict typing where reasonable: explicit type hints on `var` declarations, function parameter types, and return types. Define Resource subclasses with `class_name X extends Resource` (see the design spec at `plan/m0/00-config-and-tunables.md`).

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

## Working through the godot-ai-plugin MCP

When an agent session has the `godot` MCP server registered (per ADR 0008 / the addon junction), these rules apply.

> **Source of truth:** the plugin's MCP `instructions` block at `godot-ai-plugin/mcp-server/src/index.ts`. This section mirrors that text because the system-reminder version is truncated mid-list when delivered to agents. If the plugin instructions change, update this section.

### Key rules for game development

- Use `"."` or `""` for scene root when creating nodes (not `"/root/Node2D"`).
- Verify newly-created nodes with `godot_get_scene_tree`.
- Confirm property writes by reading them back with `godot_get_node_properties`.
- Surface parse errors via `godot_get_editor_log(filter: "error")` after every script write.
- Save scenes immediately after setting `@export` properties (they can reset on script changes).
- Use explicit types in GDScript for cross-script calls and array/dict access (`var pos: Vector2 = ...`) to avoid type-inference errors.
- Prefer `* 0.5` over `/ 2` for integer division to avoid `INTEGER_DIVISION` warnings.
- Build games iteratively: implement one feature, verify it works, then move on.

### Prefer editor APIs over direct file modification

- Scene changes (nodes, properties, positions): use `godot_create_node`, `godot_set_property`, `godot_save_scene`, etc.
- Script content (`.gd` files): use `godot_write_file` (the only sanctioned file-writing case).
- **NEVER** modify `.gd` or `.tscn` files directly on disk via shell or external editors. That bypasses the editor and triggers blocking "Files modified outside Godot" reload dialogs.
- Direct file modification is a last resort when no MCP tool exists for the operation.

### Prefer specialized tools over generic ones

- Meshes: `godot_create_primitive_mesh` instead of `godot_create_node` + `godot_set_property`.
- Collision shapes: `godot_create_collision_shape_3d`.
- Particles: `godot_apply_particle_preset` or `godot_create_particle_material_2d/3d`.
- Physics bodies: `godot_configure_rigid_body_2d/3d`, `godot_configure_character_body_2d/3d`.
- Materials: the material tools (`godot_configure_pbr_material`, `godot_create_shader_material`).
- Animations: animation tools (`godot_create_animation`, `godot_add_animation_track`, `godot_set_animation_keyframe`).
- Cameras: `godot_configure_camera3d`, `godot_set_camera3d_target/follow/orbit`.
- `godot_set_property` is for simple one-off property changes; use `configure_*` tools for multi-property setup.

### Editor vs runtime tools

- Editor scene inspection: `godot_get_scene_tree`, `godot_get_node_properties`. Show the saved scene.
- Runtime / live game inspection: `godot_get_runtime_scene_tree`, `godot_get_runtime_node_properties`. Only work while a game is running and show live game state.
- Do NOT mix them up.

### Script inspection

- For script overview: `godot_get_script_info` (methods, signals, exports counts).
- For detailed content: `godot_get_script_methods`, `godot_get_script_signals`, `godot_get_script_exports`.
- Do NOT read `.gd` files with `godot_read_file` to understand script structure — use the inspection tools.

### Testing and verification

The "Key rules" section above covers the post-script and post-property-write checks. A few additional practices specific to running and exercising a game build:

- Run a build with `godot_run_game`; capture what renders via `godot_capture_game_viewport`.
- During gameplay, inspect live state with `godot_get_runtime_node_properties` (editor `godot_get_node_properties` shows the SAVED scene, not the running game).
- Drive input mechanics from the agent via the input injection tools instead of asking the user to press keys.
- Check `godot_get_dialogs` after any file operation that could trigger a modal — dialogs block all subsequent commands until dismissed.

### Tool discovery (compact profile, the default)

- Core tools plus `godot_tool_catalog` and `godot_manage_tool_groups` are visible by default.
- Use `godot_tool_catalog` with a query (e.g. `"animation"`) to find more — matched groups are auto-activated so the tools become immediately available.
- `godot_manage_tool_groups` lists, activates, or deactivates tool groups manually.

### When the MCP server is NOT available

If the agent session doesn't have the `godot` MCP registered (e.g. fresh clone without the addon junction set up), all of the above is moot — work through normal tools (`Edit`, `Write`, `Bash`) but keep Godot **closed** while editing `.gd`/`.tscn` files to avoid the "modified outside Godot" reload dialog.

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
