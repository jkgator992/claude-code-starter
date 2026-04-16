#!/usr/bin/env bash
# UserPromptSubmit: inject repo-specific context at the start of each prompt.
# Stdout from this hook is appended to the user's prompt as additional context.
set -euo pipefail

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no git)")
status=$(git status --porcelain 2>/dev/null | head -5 || true)

cat <<EOF
<repo-context>
branch: $branch
EOF

# TODO: customize the lines below to restate your layer model / non-negotiable
# rules. Anything printed here goes into Claude's context for this prompt.
cat <<'EOF'
reminders:
  - follow the layer model in CLAUDE.md
  - never commit .env files; update .env.example instead
  - schema changes go through migrations
EOF

if [[ -n "$status" ]]; then
  echo "uncommitted changes (first 5):"
  echo "$status" | sed 's/^/  /'
fi

echo "</repo-context>"
exit 0
