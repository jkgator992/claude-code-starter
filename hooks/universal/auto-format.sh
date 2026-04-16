#!/usr/bin/env bash
# PostToolUse: format files that were just written/edited.
# Advisory — never fails the turn. Uses prettier if available.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
[[ -z "$file" || ! -f "$file" ]] && exit 0

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.md|*.mjs|*.cjs)
    if command -v prettier >/dev/null 2>&1; then
      prettier --write --log-level=warn "$file" >/dev/null 2>&1 || true
    elif [[ -x node_modules/.bin/prettier ]]; then
      node_modules/.bin/prettier --write --log-level=warn "$file" >/dev/null 2>&1 || true
    fi
    ;;
  *.py)
    # TODO: wire up your Python formatter (black, ruff format, autopep8).
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$file" >/dev/null 2>&1 || true
    elif command -v black >/dev/null 2>&1; then
      black --quiet "$file" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
