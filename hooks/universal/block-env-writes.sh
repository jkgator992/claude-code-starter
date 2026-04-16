#!/usr/bin/env bash
# PreToolUse guard: never write to real .env files. .env.example is fine.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
base=$(basename "$file")

case "$base" in
  .env.example) exit 0 ;;
  .env|.env.local|.env.development|.env.production|.env.*.local|.env.*)
    echo "block-env-writes: refusing to write $file — env files are user-managed" >&2
    echo "  Edit .env.example to document new variables instead." >&2
    exit 2
    ;;
esac

exit 0
