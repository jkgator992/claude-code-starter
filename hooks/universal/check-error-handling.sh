#!/usr/bin/env bash
# PostToolUse advisory: flag silent-failure patterns in server code.
#
# Scope: server-side directories only (apps/api/**, server/**, backend/**).
# TODO: adjust the path match list below to match your server directory layout.
#
# Advisory (exit 1): prints warnings but does not undo the edit.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

# Scope: only server-side product code, skip tests.
# TODO: add your server path patterns.
case "$file" in
  */apps/api/*.ts|*/apps/api/*.js|*/apps/api/*.mjs|*/apps/api/*.cjs) : ;;
  */server/*.ts|*/server/*.js|*/server/*.mjs|*/server/*.cjs) : ;;
  */backend/*.ts|*/backend/*.js|*/backend/*.mjs|*/backend/*.cjs) : ;;
  *) exit 0 ;;
esac
case "$file" in
  *.test.ts|*.test.js|*.spec.ts|*.spec.js|*__tests__*) exit 0 ;;
esac
[[ ! -f "$file" ]] && exit 0

warnings=()

# (1) Empty catch blocks — the classic silent failure.
while IFS= read -r match; do
  warnings+=("empty catch block at ${match%%:*} — swallows the error silently")
done < <(grep -En 'catch\s*(\([^)]*\))?\s*\{\s*\}' "$file" || true)

# (2) .then() without a .catch() nearby.
while IFS= read -r lineno; do
  warnings+=(".then() without .catch() at line ${lineno} — unhandled rejection risk")
done < <(
  awk '
    /await[[:space:]].*\.then\(/ { next }
    /\.then\(/ {
      if ($0 ~ /\.catch\(/) next
      found_catch = 0
      for (i = 1; i <= 3; i++) {
        if ((getline nxt) > 0 && nxt ~ /\.catch\(/) { found_catch = 1; break }
      }
      if (!found_catch) print NR
    }
  ' "$file"
)

# (3) Catch blocks that only log (no rethrow, no failure signal).
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r lineno; do
    [[ -z "$lineno" ]] && continue
    warnings+=("catch block at line ${lineno} only logs — handlers in server code should rethrow or signal failure")
  done < <(
    python3 - "$file" <<'PY' 2>/dev/null || true
import re, sys
try:
    src = open(sys.argv[1]).read()
except Exception:
    sys.exit(0)
pat = re.compile(
    r'catch\s*\([^)]*\)\s*\{\s*console\.(?:log|error|warn)\s*\([^)]*\)\s*;?\s*\}',
    re.MULTILINE,
)
for m in pat.finditer(src):
    line = src[:m.start()].count("\n") + 1
    print(line)
PY
  )
fi

# (4) File-level coverage: async entry-point without any try/catch.
defines_async_entrypoint=0
if grep -Eq '^\s*export\s+async\s+function\b' "$file"; then defines_async_entrypoint=1; fi
if grep -Eq '^\s*export\s+const\s+[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*async\b' "$file"; then defines_async_entrypoint=1; fi
if grep -Eq 'new\s+Worker\s*\([^)]*,\s*async\b' "$file"; then defines_async_entrypoint=1; fi

if (( defines_async_entrypoint == 1 )) && ! grep -Eq '\btry\s*\{' "$file"; then
  warnings+=("file defines an async entry point but has zero try/catch blocks — heuristic, review carefully")
fi

if (( ${#warnings[@]} == 0 )); then
  exit 0
fi

echo "check-error-handling: silent-failure patterns in $file" >&2
for w in "${warnings[@]}"; do echo "  - $w" >&2; done
echo "  Advisory: review before merging. Webhooks and workers must propagate failure so retries work." >&2
exit 1
