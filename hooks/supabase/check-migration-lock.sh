#!/usr/bin/env bash
# .claude/hooks/check-migration-lock.sh
#
# Enforces the migration-lock protocol. Any commit that adds or modifies a
# file under supabase/migrations/ must be made from the worktree that holds
# the lock. Prevents two parallel Claude Code sessions from both writing
# migrations at once, which corrupts schema state.
#
# Integration: called by .claude/hooks/pre-commit-gate.sh. Also callable
# standalone for --status introspection.
#
# Usage:
#   check-migration-lock.sh           # enforce; exits non-zero on violation
#   check-migration-lock.sh --status  # print current lock state, exit 0
#   check-migration-lock.sh --release # release lock if held by this ticket

set -euo pipefail

# -----------------------------------------------------------------------------
# Locate coordination state
# -----------------------------------------------------------------------------
GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null)"
if [ -z "$GIT_COMMON_DIR" ]; then
  echo "ERROR: not inside a git repository" >&2
  exit 2
fi

COORD="$GIT_COMMON_DIR/../project-coordination"
mkdir -p "$COORD"
LOCK="$COORD/migration-lock"

# -----------------------------------------------------------------------------
# Identify current ticket from the worktree
# -----------------------------------------------------------------------------
TICKET_FILE="docs/current-ticket.md"
CURRENT_TICKET=""
if [ -f "$TICKET_FILE" ]; then
  CURRENT_TICKET=$(grep -oE '[A-Z][A-Z0-9]+-[0-9]+' "$TICKET_FILE" | head -n1 || true)
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
lock_holder() {
  [ -f "$LOCK" ] && head -n1 "$LOCK" || echo ""
}

lock_age_seconds() {
  if [ ! -f "$LOCK" ]; then
    echo "0"
    return
  fi
  local now mtime
  now=$(date +%s)
  # macOS vs Linux stat
  mtime=$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK")
  echo $((now - mtime))
}

has_migration_changes() {
  # Check staged (for pre-commit hook) and modified (for standalone)
  git diff --cached --name-only | grep -qE '^supabase/migrations/' && return 0
  git diff --name-only      | grep -qE '^supabase/migrations/' && return 0
  return 1
}

# -----------------------------------------------------------------------------
# Mode: --status
# -----------------------------------------------------------------------------
if [ "${1:-}" = "--status" ]; then
  HOLDER=$(lock_holder)
  if [ -z "$HOLDER" ]; then
    echo "migration-lock: FREE"
  else
    AGE_S=$(lock_age_seconds)
    AGE_H=$((AGE_S / 3600))
    AGE_M=$(( (AGE_S % 3600) / 60 ))
    echo "migration-lock: held by $HOLDER"
    echo "age: ${AGE_H}h ${AGE_M}m"
    if [ "$AGE_S" -gt 14400 ]; then
      echo "WARNING: lock is stale (> 4h). Consider force-release if holder is idle."
    fi
  fi
  echo "current worktree ticket: ${CURRENT_TICKET:-"(none — no docs/current-ticket.md)"}"
  exit 0
fi

# -----------------------------------------------------------------------------
# Mode: --release
# -----------------------------------------------------------------------------
if [ "${1:-}" = "--release" ]; then
  HOLDER=$(lock_holder)
  if [ -z "$HOLDER" ]; then
    echo "migration-lock is not held"
    exit 0
  fi
  if [ "$HOLDER" != "$CURRENT_TICKET" ]; then
    echo "ERROR: migration-lock is held by $HOLDER, not $CURRENT_TICKET" >&2
    echo "Use --force-release only if you know the holder is idle." >&2
    exit 1
  fi
  rm "$LOCK"
  echo "Released migration-lock (was held by $HOLDER)"
  exit 0
fi

# -----------------------------------------------------------------------------
# Mode: --force-release (dangerous, prompts)
# -----------------------------------------------------------------------------
if [ "${1:-}" = "--force-release" ]; then
  HOLDER=$(lock_holder)
  if [ -z "$HOLDER" ]; then
    echo "migration-lock is not held"
    exit 0
  fi
  AGE_S=$(lock_age_seconds)
  AGE_H=$((AGE_S / 3600))
  echo "About to force-release migration-lock held by $HOLDER (age: ${AGE_H}h)."
  echo "This is safe ONLY if $HOLDER's worktree is idle / complete."
  read -r -p "Type the holder ticket ID to confirm: " CONFIRM
  if [ "$CONFIRM" != "$HOLDER" ]; then
    echo "Mismatch — aborted."
    exit 1
  fi
  rm "$LOCK"
  echo "Force-released migration-lock"
  # Record in audit log
  mkdir -p "$GIT_COMMON_DIR/../.claude"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) FORCE_RELEASE migration-lock was=$HOLDER by=$CURRENT_TICKET" \
    >> "$GIT_COMMON_DIR/../.claude/audit.log"
  exit 0
fi

# -----------------------------------------------------------------------------
# Default mode: enforce
# -----------------------------------------------------------------------------

# Not touching migrations? Nothing to check.
if ! has_migration_changes; then
  exit 0
fi

# Touching migrations but no current ticket context
if [ -z "$CURRENT_TICKET" ]; then
  echo "❌ MIGRATION LOCK VIOLATION" >&2
  echo "" >&2
  echo "Staged/changed files include supabase/migrations/ but this worktree" >&2
  echo "has no docs/current-ticket.md." >&2
  echo "" >&2
  echo "Migrations may only be written from a worktree started with:" >&2
  echo "  /ticket-start <TICKET-KEY>" >&2
  echo "" >&2
  echo "This is not optional. Parallel migration writes corrupt schema state." >&2
  exit 1
fi

# Touching migrations, have a ticket — lock must exist and match
HOLDER=$(lock_holder)

if [ -z "$HOLDER" ]; then
  echo "❌ MIGRATION LOCK NOT HELD" >&2
  echo "" >&2
  echo "This worktree ($CURRENT_TICKET) is adding migrations but does not" >&2
  echo "hold the migration-lock." >&2
  echo "" >&2
  echo "/ticket-start should have acquired the lock. Either:" >&2
  echo "  1. Re-run /ticket-start to acquire it properly, or" >&2
  echo "  2. Manually: echo '$CURRENT_TICKET' > $LOCK" >&2
  echo "" >&2
  echo "Then retry the commit." >&2
  exit 1
fi

if [ "$HOLDER" != "$CURRENT_TICKET" ]; then
  AGE_S=$(lock_age_seconds)
  AGE_H=$((AGE_S / 3600))
  echo "❌ MIGRATION LOCK HELD BY ANOTHER TICKET" >&2
  echo "" >&2
  echo "  This worktree:  $CURRENT_TICKET" >&2
  echo "  Lock holder:    $HOLDER" >&2
  echo "  Lock age:       ${AGE_H}h" >&2
  echo "" >&2
  echo "Two tickets cannot write migrations in parallel." >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  1. Wait for $HOLDER to merge and release the lock." >&2
  echo "  2. Coordinate with the holder — maybe combine into one migration." >&2
  echo "  3. If $HOLDER is idle/complete (stale):" >&2
  echo "       .claude/hooks/check-migration-lock.sh --force-release" >&2
  echo "     then re-run /ticket-start to acquire." >&2
  exit 1
fi

# Lock held by this ticket — clear to proceed
exit 0
