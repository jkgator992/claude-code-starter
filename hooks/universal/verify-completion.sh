#!/usr/bin/env bash
# Stop hook: if Claude's final message claims work is complete, run typecheck
# silently and log the result. Never blocks — informational only.
#
# Outputs: docs/completion-log.md — append-only log of every claim + result.
#
# TODO: replace `npm run typecheck` at the bottom if you use a different
# type checker (pnpm, yarn, mypy, etc.).
set -euo pipefail

payload=$(cat)

active=$(echo "$payload" | jq -r '.stop_hook_active // false')
if [[ "$active" == "true" ]]; then
  exit 0
fi

transcript=$(echo "$payload" | jq -r '.transcript_path // ""')
[[ -z "$transcript" ]] && exit 0
[[ ! -f "$transcript" ]] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0

last_text=$(
  python3 - "$transcript" <<'PY' 2>/dev/null || true
import json, sys
try:
    path = sys.argv[1]
    last = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            role = obj.get("role") or obj.get("type")
            if role != "assistant":
                continue
            msg = obj.get("message") or obj
            content = msg.get("content")
            if isinstance(content, str):
                last = content
            elif isinstance(content, list):
                parts = []
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "text":
                        parts.append(c.get("text", ""))
                if parts:
                    last = "\n".join(parts)
    if last:
        sys.stdout.write(last)
except Exception:
    pass
PY
)

[[ -z "$last_text" ]] && exit 0

claim=$(
  printf '%s' "$last_text" | python3 - <<'PY' 2>/dev/null || true
import re, sys
text = sys.stdin.read()
triggers = [
    "all set", "ready to commit", "ready for review",
    "complete", "completed", "done", "finished", "working",
    "implemented", "ready", "deployed",
]
pat = re.compile(r"\b(" + "|".join(re.escape(t) for t in triggers) + r")\b", re.IGNORECASE)
m = pat.search(text)
if m:
    sys.stdout.write(m.group(1).lower())
PY
)

[[ -z "$claim" ]] && exit 0

log="/tmp/starter-verify-completion-$$.log"
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no git)")

# TODO: change this to match your project's typecheck command.
TYPECHECK_CMD="${TYPECHECK_CMD:-npm run typecheck}"
if eval "$TYPECHECK_CMD" > "$log" 2>&1; then
  verdict="✅"
  passed=1
else
  verdict="❌"
  passed=0
fi

cl="docs/completion-log.md"
if [[ ! -f "$cl" ]]; then
  mkdir -p "$(dirname "$cl")"
  cat > "$cl" <<'EOF'
# Completion Log

Auto-captured by `verify-completion.sh` whenever Claude claims a task is
complete. Each entry records the timestamp, branch, the claim word, and
whether the typecheck passed at that moment.

EOF
fi
safe_claim=${claim//|/\\|}
echo "- ${verdict} ${ts} \`${branch}\` — \"${safe_claim}\" — typecheck: $([[ $passed -eq 1 ]] && echo passed || echo failed)" >> "$cl"

if [[ $passed -eq 0 ]]; then
  echo "verify-completion: Claude claimed \"${claim}\" but typecheck failed" >&2
  echo "  log: $log" >&2
  if grep -Eq 'error (TS[0-9]+|\[|:)' "$log"; then
    echo "  first errors:" >&2
    grep -E 'error (TS[0-9]+|\[|:)' "$log" | head -10 | sed 's/^/    /' >&2
  fi
  exit 1
fi

rm -f "$log"
exit 0
