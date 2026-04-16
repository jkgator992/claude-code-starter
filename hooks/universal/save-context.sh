#!/usr/bin/env bash
# Stop hook: snapshot current git state so later sessions can reconstruct context.
set -euo pipefail

out=".claude/last-session.md"
mkdir -p "$(dirname "$out")"

{
  echo "# Last session snapshot"
  echo
  echo "_Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")_"
  echo
  echo "## Branch"
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no git)"
  echo
  echo "## Status"
  echo '```'
  git status --short 2>/dev/null || true
  echo '```'
  echo
  echo "## Recent commits"
  echo '```'
  git log --oneline -10 2>/dev/null || true
  echo '```'
} > "$out"

exit 0
