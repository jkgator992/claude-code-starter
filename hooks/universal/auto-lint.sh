#!/usr/bin/env bash
# PostToolUse: run eslint --fix (or ruff check --fix) on touched files.
# Advisory only — never fail the turn.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
[[ -z "$file" || ! -f "$file" ]] && exit 0

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    if [[ -x node_modules/.bin/eslint ]]; then
      node_modules/.bin/eslint --fix "$file" >/dev/null 2>&1 || true
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff check --fix "$file" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
