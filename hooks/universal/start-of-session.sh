#!/usr/bin/env bash
# SessionStart hook: print a compact session primer on stdout.
# Claude Code injects this output as context before the first user message.
#
# Reads from, but never writes to:
#   - .claude/sessions/resume-{safe-branch}-*.md   (latest by filename timestamp)
#   - docs/violations.md                           (❌ count)
#   - docs/tests/test-results.csv                  (failing count)
#   - docs/gotchas.md                              (first 20 lines)
set -euo pipefail

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
safe_branch=${branch//\//-}

uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

unresolved_violations=0
if [[ -f docs/violations.md ]]; then
  unresolved_violations=$(grep -c '^❌' docs/violations.md 2>/dev/null || echo 0)
fi

failing_tests="(no test-results.csv yet)"
if [[ -f docs/tests/test-results.csv ]]; then
  fails=$(grep -ic 'fail' docs/tests/test-results.csv 2>/dev/null || echo 0)
  failing_tests="$fails"
fi

# TODO: if you use Taskmaster, uncomment the next_task block.
next_task="(task-master not installed)"
# if command -v task-master >/dev/null 2>&1; then
#   next_task=$(task-master next 2>/dev/null | head -10 || true)
#   [[ -z "$next_task" ]] && next_task="(none)"
# fi

LATEST=""
if [[ -d .claude/sessions ]]; then
  LATEST=$(ls -1 .claude/sessions/resume-"${safe_branch}"-*.md 2>/dev/null | sort | tail -1 || true)
fi

cat <<EOF
<session-start>
# Session Start — branch \`${branch}\`

## Recent commits
\`\`\`
$(git log --oneline -3 2>/dev/null || echo '(no git history)')
\`\`\`

## Status
- uncommitted files: ${uncommitted}
- unresolved violations: ${unresolved_violations}
- failing tests: ${failing_tests}

## Next task
${next_task}

## Resume context
EOF

if [[ -n "$LATEST" && -f "$LATEST" ]]; then
  echo "_from: $LATEST_"
  echo
  head -100 "$LATEST"
else
  echo "_(no prior session file for branch \`${branch}\` — fresh clone or first session)_"
fi

# TODO: Insert a few project-specific reminders here (layer model,
# inviolable rules, secrets boundaries). The installer replaces this block.
cat <<'EOF'

## Project reminders
- See CLAUDE.md for the layer model and non-negotiable rules.
- Schema changes go through migrations; never hand-edit generated types.
- Every mutation on critical entities writes to an audit log.

## Top gotchas (head of docs/gotchas.md)
EOF

if [[ -f docs/gotchas.md ]]; then
  echo '```markdown'
  head -20 docs/gotchas.md
  echo '```'
else
  echo "_(docs/gotchas.md not present yet — will be scaffolded on first capture)_"
fi

echo "</session-start>"
exit 0
