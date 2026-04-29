#!/usr/bin/env bash
# PostToolUse hook: language aware format on save.
# Receives Claude Code hook JSON on stdin. Looks at .tool_input.file_path
# and runs the appropriate formatter. Best effort: never blocks the agent
# (always exits 0). Missing tools are silently skipped.
set -uo pipefail

input=$(cat)

# Extract file_path; fall back to empty if jq missing or path absent
if command -v jq >/dev/null 2>&1; then
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
else
  # Fallback: best effort grep for the file_path field
  file_path=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi

if [[ -z "$file_path" || ! -f "$file_path" ]]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Resolve absolute path so prefix matches work regardless of how the path was supplied
abs_path=$(readlink -f "$file_path" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$file_path")

case "$abs_path" in
  *.cs)
    if [[ -d "$PROJECT_DIR/client" ]] && command -v dotnet >/dev/null 2>&1; then
      if [[ -f "$PROJECT_DIR/client/Clash.sln" ]] || ls "$PROJECT_DIR"/client/*.csproj >/dev/null 2>&1; then
        (cd "$PROJECT_DIR/client" && dotnet format --include "$abs_path" >/dev/null 2>&1) || true
      fi
    fi
    ;;
  *.gd)
    command -v gdformat >/dev/null 2>&1 && gdformat "$abs_path" >/dev/null 2>&1 || true
    ;;
  *.go)
    command -v golangci-lint >/dev/null 2>&1 && golangci-lint fmt "$abs_path" >/dev/null 2>&1 || true
    ;;
  *.proto)
    command -v buf >/dev/null 2>&1 && (cd "$PROJECT_DIR" && buf format -w "$abs_path" >/dev/null 2>&1) || true
    ;;
esac

exit 0
