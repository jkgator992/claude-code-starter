#!/usr/bin/env bash
# PostToolUse: append a line to .claude/audit.log for every file write/edit.
# Useful for tracing what Claude touched during a session.
set -euo pipefail

payload=$(cat)
tool=$(echo "$payload" | jq -r '.tool_name // "?"')
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

[[ -z "$file" ]] && exit 0

log=".claude/audit.log"
mkdir -p "$(dirname "$log")"
echo "$ts  $tool  $file" >> "$log"

exit 0
