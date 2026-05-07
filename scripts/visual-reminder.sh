#!/usr/bin/env bash
# PostToolUse hook: emit a reminder when Claude edits a Godot scene under
# client/scenes/. The reminder nudges the agent to run
# `godot_capture_game_viewport` and the `visual-reviewer` subagent before
# declaring visual work done. See plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md.
#
# Best effort: never blocks the agent (always exits 0). Reminder is a
# stderr message — does not modify or stage files.
set -uo pipefail

input=$(cat)

# Extract file_path; jq if available, regex fallback otherwise.
if command -v jq >/dev/null 2>&1; then
	file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
else
	file_path=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi

if [[ -z "$file_path" ]]; then
	exit 0
fi

# Match client/scenes/**/*.tscn or client/data/entity_visuals.tres.
# Use case-insensitive substring checks to keep it portable.
shopt -s nocasematch
if [[ "$file_path" == *"client/scenes/"*".tscn" || "$file_path" == *"client/data/entity_visuals.tres" ]]; then
	echo "[visual-reminder] Visual file changed: $file_path" >&2
	echo "[visual-reminder] Before declaring this done: run godot_capture_game_viewport and invoke the visual-reviewer subagent against docs/visual-spec.md + docs/visual-references/." >&2
fi

exit 0
