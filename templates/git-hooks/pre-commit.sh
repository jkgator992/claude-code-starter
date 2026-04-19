#!/usr/bin/env bash
# Git pre-commit hook installed by claude-code-starter v0.2.2.
# Only runs the migration-lock check — lightweight, fires on every
# terminal commit. For the full PreToolUse gate (typecheck, lint,
# secret scan, etc.), use Claude Code which runs pre-commit-gate.sh
# via its PreToolUse Bash hook.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Only gate commits that touch supabase/migrations/**
staged_migrations=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '^supabase/migrations/' || true)
if [[ -z "$staged_migrations" ]]; then
  exit 0
fi

lock_check="$repo_root/.claude/hooks/check-migration-lock.sh"
if [[ ! -x "$lock_check" ]]; then
  # Hook not installed (consumer removed it?) — fail open with warning
  echo "WARNING: .claude/hooks/check-migration-lock.sh missing or not executable; terminal commit gate skipped." >&2
  exit 0
fi

if ! "$lock_check"; then
  echo "" >&2
  echo "Terminal commit blocked by migration lock check." >&2
  echo "Either hold the migration lock for this ticket, or commit via Claude Code." >&2
  exit 1
fi

exit 0
