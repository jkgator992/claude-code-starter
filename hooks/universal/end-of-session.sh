#!/usr/bin/env bash
# SessionEnd hook: write a per-branch resume snapshot that start-of-session.sh
# can pick up on the next session.
#
# Filename: .claude/sessions/resume-{safe-branch}-{YYYYMMDDTHHMMSSZ}.md
#
# Rotation: keeps the 10 most recent per branch.
# Never blocks — always exits 0.
set -euo pipefail

_=$(cat || true)

mkdir -p .claude/sessions

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
safe_branch=${branch//\//-}
ts=$(date -u +"%Y%m%dT%H%M%SZ")
iso_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
out=".claude/sessions/resume-${safe_branch}-${ts}.md"

# TODO: if you use Taskmaster, uncomment the next_task block.
next_task="(task-master not installed)"
# if command -v task-master >/dev/null 2>&1; then
#   next_task=$(task-master next 2>/dev/null | head -10 || true)
#   [[ -z "$next_task" ]] && next_task="(none)"
# fi

# ─── Unresolved violations ──────────────────────────────────────────────────
violations=""
if [[ -f docs/violations.md ]]; then
  violations=$(grep '^❌' docs/violations.md 2>/dev/null || true)
fi

# ─── Mid-session notes written by save-context.sh ───────────────────────────
last_session=""
if [[ -f .claude/last-session.md ]]; then
  last_session=$(cat .claude/last-session.md)
fi

{
  echo "# Session resume for \`${branch}\`"
  echo
  echo "_Written: ${iso_ts}_"
  echo "_File: ${out}_"
  echo
  echo "## Recent commits"
  echo '```'
  git log --oneline -5 2>/dev/null || echo '(no git history)'
  echo '```'
  echo
  echo "## Uncommitted changes"
  echo '```'
  git status --short 2>/dev/null || echo '(no git)'
  echo '```'
  echo
  echo "## Next task"
  echo "${next_task}"
  echo
  if [[ -n "$violations" ]]; then
    echo "## Unresolved violations (docs/violations.md)"
    echo '```'
    echo "$violations"
    echo '```'
    echo
  fi
  if [[ -n "$last_session" ]]; then
    echo "## Mid-session notes"
    echo "${last_session}"
    echo
  fi
  # TODO: add project-specific reminders here (layer model, secrets boundaries, etc.)
} > "$out"

# Rotation: keep 10 most recent per branch.
count=$(ls -1 .claude/sessions/resume-"${safe_branch}"-*.md 2>/dev/null | wc -l | tr -d ' ')
if (( count > 10 )); then
  excess=$(( count - 10 ))
  ls -1 .claude/sessions/resume-"${safe_branch}"-*.md 2>/dev/null \
    | sort \
    | head -n "$excess" \
    | while IFS= read -r old; do
        [[ -f "$old" ]] && rm -f "$old"
      done
fi

exit 0
