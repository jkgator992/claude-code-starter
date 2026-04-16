#!/usr/bin/env bash
# PreToolUse guard: enforce Layer 1 rule — only your data-access layer may
# call supabase.from() / .rpc() or instantiate a Supabase client.
#
# TODO: set LAYER1_PATH to the one directory that is allowed to call Supabase
# directly in your codebase. Common choices:
#   packages/database/operations/
#   src/db/
#   lib/database/
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
content=$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // ""')

# Only inspect product TS/JS/TSX/JSX files.
case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) : ;;
  *) exit 0 ;;
esac

# TODO: update this path to your data-access layer.
LAYER1_PATH="${LAYER1_PATH:-packages/database/operations/}"

# Layer 1 is the one place these calls are allowed.
if [[ "$file" == *"$LAYER1_PATH"* ]]; then
  exit 0
fi

violations=()

if echo "$content" | grep -Eq 'supabase\s*\.\s*from\s*\('; then
  violations+=("supabase.from(...) — move this query into $LAYER1_PATH")
fi
if echo "$content" | grep -Eq 'supabase\s*\.\s*rpc\s*\('; then
  violations+=("supabase.rpc(...) — move this RPC call into $LAYER1_PATH")
fi

# createClient from @supabase/supabase-js anywhere outside Layer 1 or the
# thin auth wrappers.
# TODO: adjust the allow-list below for any per-app auth wrapper directories.
if echo "$content" | grep -Eq "from\s+['\"]@supabase/supabase-js['\"]"; then
  case "$file" in
    */apps/*/lib/supabase/*|*/apps/*/src/lib/supabase/*) : ;;
    */src/lib/supabase/*|*/lib/supabase/*) : ;;
    *)
      if echo "$content" | grep -Eq '\bcreateClient\s*\('; then
        violations+=("createClient(@supabase/supabase-js) — clients belong in $LAYER1_PATH or a dedicated lib/supabase/ directory")
      fi
      ;;
  esac
fi

if (( ${#violations[@]} > 0 )); then
  echo "check-direct-supabase: Layer 1 violation in $file" >&2
  for v in "${violations[@]}"; do echo "  - $v" >&2; done
  echo "  See: CLAUDE.md 'Layer Rules'" >&2
  exit 2
fi

exit 0
