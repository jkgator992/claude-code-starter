# Project coordination

This directory lives at `$(git rev-parse --git-common-dir)/../project-coordination`
and is SHARED across all git worktrees of this repository. It holds the
coordination state that enables parallel Claude Code sessions to work on
different tickets without stepping on each other.

It is **gitignored** — coordination state is local to your machine.

## Files

### `active-worktrees.md`

The registry of in-flight tickets. One line per active worktree. Managed by
`/ticket-start` (append) and `/ticket-close` (remove). Read by
`/ticket-start`'s overlap-detection step and by `/worktrees`.

Format (pipe-separated, single line per entry):

```
SCRUM-142 | ../<PROJECT_SLUG>-SCRUM-142 | feature/SCRUM-142-campaigns | started: 2026-04-18T14:22:10Z | write: supabase/migrations/**, packages/database/operations/campaigns/** | locks: migration
SCRUM-143 | ../<PROJECT_SLUG>-SCRUM-143 | feature/SCRUM-143-api       | started: 2026-04-18T15:01:45Z | write: apps/api/src/routes/campaigns/** | locks:
SCRUM-144 | ../<PROJECT_SLUG>-SCRUM-144 | feature/SCRUM-144-ui        | started: 2026-04-18T15:15:02Z | write: apps/mobile/app/donations/** | locks:
```

### `migration-lock`

Exists only when a ticket holds the lock. Two-line file:

```
SCRUM-142
2026-04-18T14:22:10Z
```

Line 1: ticket ID holding the lock. Line 2: ISO timestamp when acquired.

Managed by `/ticket-start` (acquire), `/ticket-close` (release),
`.claude/hooks/check-migration-lock.sh` (enforce on commit).

## Why this lives outside `.claude/`

Each git worktree has its own `.claude/` directory (copied from the main
checkout's `.claude/`, then each worktree's gitignored files diverge). If
coordination state lived inside any single worktree's `.claude/`, the other
worktrees wouldn't see it.

`git rev-parse --git-common-dir` returns the path to the shared `.git/`
directory that all worktrees of the same repo share. `../project-coordination`
(sibling of that) is reliably visible from every worktree.

## Why not inside `.git/`?

`.git/` is managed by git itself. Putting custom files there risks
interaction with git GC and worktree operations. The sibling directory is
safer.

## Stale state recovery

Run:

```bash
/worktrees --clean
```

This identifies:
- Entries in `active-worktrees.md` whose worktree no longer exists (stale)
- Worktrees on disk missing from `active-worktrees.md` (orphan)
- `migration-lock` held by a ticket that isn't in `active-worktrees.md`
  (zombie)
- `migration-lock` older than 4 hours (stale)

Each is shown with a prompt. Nothing auto-deletes.

## Manual cleanup (rarely needed)

```bash
COORD="$(git rev-parse --git-common-dir)/../project-coordination"

# View current state
cat "$COORD/active-worktrees.md"
cat "$COORD/migration-lock" 2>/dev/null || echo "(no lock)"

# Nuclear option — only if /worktrees --clean can't recover and you've
# confirmed all active worktrees are genuinely finished
rm -rf "$COORD"

# Rebuild by re-running /ticket-start on any tickets still in progress
```

## What's NOT in here

- Per-session state (`.claude/sessions/`, `.claude/last-session.md`, etc.)
  — those live in each worktree's own `.claude/` and should not be shared.
- Build artifacts, node_modules, test output — per-worktree.
- `docs/violations.md`, `docs/traceability.md`, `docs/completion-log.md` —
  these are committed project files, not coordination state.

## Debugging

If two sessions claim the same ticket or migrations keep conflicting:

1. Run `/worktrees` in both sessions. Compare their views.
2. Check `.claude/audit.log` in each worktree for recent dispatcher and
   hook events.
3. Verify `git worktree list` matches `active-worktrees.md` exactly.

Most coordination bugs come from someone using `git worktree add` directly
instead of `/ticket-start`. The hook catches migration writes, but nothing
catches general file overlap if you bypass the protocol.
