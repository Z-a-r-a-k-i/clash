#!/usr/bin/env bash
# PreToolUse hook on Bash: scope aware pre commit gate for clash.
# Runs only when the bash command is `git commit ...`. Detects which stacks
# are staged and runs only the relevant checks. Blocks commit on failure
# (exit 2 -> Claude Code surfaces stderr to the agent and denies the tool call).
set -uo pipefail

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
else
  command=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi

# Only act on git commit invocations
if [[ ! "$command" =~ (^|[[:space:]\;\&\|])git[[:space:]]+commit ]]; then
  exit 0
fi

# Respect explicit bypass
if [[ "$command" == *--no-verify* ]]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || { echo "pre commit gate: failed to cd to $PROJECT_DIR" >&2; exit 2; }

staged=$(git diff --cached --name-only 2>/dev/null || true)
if [[ -z "$staged" ]]; then
  exit 0
fi

has_cs=false
has_gd=false
has_go=false
has_proto=false
gd_files=""
proto_files=""

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    *.cs)    has_cs=true ;;
    *.gd)    has_gd=true; gd_files+="$f"$'\n' ;;
    *.go)    has_go=true ;;
    *.proto) has_proto=true; proto_files+="$f"$'\n' ;;
  esac
done <<< "$staged"

fail() {
  echo "" >&2
  echo "pre commit gate: $1" >&2
  echo "  (override with 'git commit --no-verify' if intentional)" >&2
  exit 2
}

if $has_cs; then
  if [[ -f client/Clash.sln ]] || ls client/*.csproj >/dev/null 2>&1; then
    echo "pre commit gate: running C# checks (dotnet format / build / test)..." >&2
    (cd client && dotnet format --verify-no-changes) >&2 \
      || fail "dotnet format would reformat files; run 'cd client && dotnet format' first"
    (cd client && dotnet build --nologo -v quiet) >&2 || fail "dotnet build failed"
    (cd client && dotnet test --nologo -v quiet) >&2 || fail "dotnet test failed"
  else
    echo "pre commit gate: skipping C# checks (no .sln/.csproj in client/)" >&2
  fi
fi

if $has_gd; then
  echo "pre commit gate: running GDScript checks (gdlint, gdformat)..." >&2
  command -v gdlint >/dev/null 2>&1 || fail "gdlint not found (install gdtoolkit: pip install gdtoolkit)"
  command -v gdformat >/dev/null 2>&1 || fail "gdformat not found (install gdtoolkit: pip install gdtoolkit)"
  printf '%s' "$gd_files" | grep -v '^$' | xargs -r gdlint >&2 || fail "gdlint failed"
  printf '%s' "$gd_files" | grep -v '^$' | xargs -r gdformat --check >&2 \
    || fail "gdformat would reformat files; run 'gdformat <files>' first"
fi

if $has_go; then
  if [[ -f server/go.mod ]]; then
    echo "pre commit gate: running Go checks (go vet, go test -race)..." >&2
    (cd server && go vet ./...) >&2 || fail "go vet failed"
    (cd server && go test -race ./...) >&2 || fail "go test failed"
  else
    echo "pre commit gate: skipping Go checks (no server/go.mod)" >&2
  fi
fi

if $has_proto; then
  echo "pre commit gate: running proto checks (buf lint, buf format, codegen no drift)..." >&2
  command -v buf >/dev/null 2>&1 || fail "buf not found (install: https://buf.build/docs/installation)"
  buf lint >&2 || fail "buf lint failed"
  printf '%s' "$proto_files" | grep -v '^$' | xargs -r buf format --diff --exit-code >&2 \
    || fail "buf format would change files; run 'buf format -w' first"
  if [[ -f buf.gen.yaml ]]; then
    echo "pre commit gate: regenerating protobuf code (buf generate)..." >&2
    buf generate >&2 || fail "buf generate failed"
    if ! git diff --quiet -- client/generated/ server/internal/proto/ 2>/dev/null; then
      fail "buf generate produced diffs in generated outputs; stage and commit them"
    fi
  fi
fi

exit 0
