#!/usr/bin/env bash
# PreToolUse guard: reject Write/Edit payloads that look like real secrets.
# Input: JSON on stdin with .tool_input.file_path and .tool_input.content / .new_string
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
content=$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // ""')

# Never block edits to example files.
case "$file" in
  */.env.example|*.example) exit 0 ;;
esac

# Heuristics for real secrets. Tight patterns to avoid false positives.
# TODO: add any project-specific key prefixes here (custom internal tokens, etc.)
if echo "$content" | grep -Eq 'sk_live_[A-Za-z0-9]{16,}'; then
  echo "block-secrets: Stripe live secret key detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'rk_live_[A-Za-z0-9]{16,}'; then
  echo "block-secrets: Stripe live restricted key detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'whsec_[A-Za-z0-9]{24,}'; then
  echo "block-secrets: Stripe webhook secret detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'sk-ant-api03-[A-Za-z0-9_-]{24,}'; then
  echo "block-secrets: Anthropic API key detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 're_[A-Za-z0-9]{24,}'; then
  echo "block-secrets: Resend API key detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'; then
  # JWT-shaped — likely a service-role/admin key pasted by mistake.
  echo "block-secrets: JWT-shaped token detected in $file (possible admin/service-role key)" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'AKIA[0-9A-Z]{16}'; then
  echo "block-secrets: AWS access key id detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'ghp_[A-Za-z0-9]{36}'; then
  echo "block-secrets: GitHub personal access token detected in $file" >&2
  exit 2
fi
if echo "$content" | grep -Eq 'xox[baprs]-[A-Za-z0-9-]{10,}'; then
  echo "block-secrets: Slack token detected in $file" >&2
  exit 2
fi

exit 0
