# /ticket-close

Closes a ticket's worktree lifecycle. Runs when the user has opened a PR (or
is about to). Updates Jira to "In Review," writes the traceability entry,
releases locks, removes the active-worktrees entry. Does NOT delete the
worktree — that happens after merge via `git worktree remove`.

## Usage

```
/ticket-close SCRUM-142
/ticket-close SCRUM-142 --pr-url https://github.com/<YOUR_ORG>/<YOUR_REPO>/pull/321
```

## What you (Claude) must do, step by step

### 1. Parse args

- Ticket key (required)
- `--pr-url` (optional but strongly recommended)
- `--force` (optional, skips verification steps)

### 2. Verify current worktree matches the ticket

```bash
# Must be run from INSIDE the ticket's worktree
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
TICKET_FILE="docs/current-ticket.md"

if [ ! -f "$TICKET_FILE" ]; then
  echo "ERROR: no docs/current-ticket.md — are you in the right worktree?"
  exit 1
fi

TICKET_IN_FILE=$(grep -oE 'SCRUM-[0-9]+' "$TICKET_FILE" | head -n1)
if [ "$TICKET_IN_FILE" != "$1" ]; then
  echo "ERROR: current worktree is for $TICKET_IN_FILE, not $1"
  exit 1
fi
```

If not in the expected worktree, STOP. Do not modify coordination state for
a ticket you're not inside. User can `cd` in and retry.

### 3. Verify the ticket is committable

Unless `--force` is passed, verify:
- Working tree is clean (`git status --porcelain` is empty) or all changes
  are staged
- A commit exists on this branch (`git log --oneline <branch>..HEAD` non-empty)
- `docs/violations.md` has no ❌ entries opened by this ticket
- `pre-launch-auditor` Tier 1 has been run on the latest commit (check
  `.claude/audit.log` for a Phase 4 SHIP entry for this ticket within last
  2 hours)

If any check fails, STOP and report. The user can re-run dispatcher, fix
issues, then retry ticket-close.

### 4. Update `docs/traceability.md`

Append a row:

```
| SCRUM-NNN | <summary> | <spec refs> | <operation files> | <test files> | In Review | <pr-url> |
```

If a row already exists for this ticket (from an earlier run), update it in
place rather than duplicating.

### 5. Release migration lock (if held by this ticket)

```bash
COORD="$(git rev-parse --git-common-dir)/../project-coordination"
LOCK="$COORD/migration-lock"

if [ -f "$LOCK" ]; then
  HOLDER=$(head -n1 "$LOCK")
  if [ "$HOLDER" = "SCRUM-NNN" ]; then
    rm "$LOCK"
    echo "Released migration-lock"
  fi
fi
```

Do NOT release a lock held by a different ticket. If the lock is held by
someone else but this ticket's `current-ticket.md` says it holds the lock,
that's a coordination bug — report it and let the user resolve.

### 6. Remove from `active-worktrees.md`

Read `$COORD/active-worktrees.md`, filter out the line for this ticket,
write back. Preserve all other entries.

### 7. Update `docs/current-ticket.md` inside the worktree

Append a closing block:

```markdown

---

## Closed
**At:** <iso-timestamp>
**PR:** <pr-url or "not provided">
**Final verdict:** SHIP (from last dispatcher Phase 4 run)
**Locks released:** <list>
**Traceability entry:** docs/traceability.md (row for SCRUM-NNN)
```

Do not delete the file. It's useful context if the PR needs revision.

### 8. Transition the Jira ticket

Get transitions via `getTransitionsForJiraIssue`. Find the one that moves
"In Progress" → "In Review" (may be named "Submit for Review," "Code
Review," etc.). Transition. Add a comment:

> PR opened: <pr-url>
> Worktree: <path>
> Closed by Claude Code via /ticket-close at <iso-timestamp>.

If `--pr-url` was not provided, comment with:

> Ticket closed locally; PR URL not yet attached. Update this ticket with
> the PR link when opened.

If the transition fails, warn but continue.

### 9. Print closing summary

```
✅ SCRUM-NNN closed.

Jira:        Transitioned to In Review
Traceability: docs/traceability.md updated
Locks:       <list of released locks, or "none held">
Worktree:    <path> — PRESERVED (delete after merge with: git worktree remove)

Active worktrees now: <count>

After the PR merges:
  git worktree remove ../<PROJECT_SLUG>-SCRUM-NNN
  git branch -d feature/SCRUM-NNN-slug
```

## Post-merge cleanup (user runs manually)

After the PR merges to main, the user runs:

```bash
cd /path/to/main/<PROJECT_SLUG>  # parent repo
git worktree remove ../<PROJECT_SLUG>-SCRUM-NNN
git branch -d feature/SCRUM-NNN-slug
# Optional: prune stale worktree metadata
git worktree prune
```

This is NOT part of /ticket-close because merge timing is not deterministic
and the worktree is useful for post-merge hotfixes if reviewers request
changes.

## Error handling

- **Not in ticket's worktree** — stop, require cd.
- **Dirty working tree** — stop unless `--force`, require commit or stash.
- **`pre-launch-auditor` Tier 1 never ran (or not SHIP)** — stop unless
  `--force`, require running dispatcher Phase 4 first.
- **Lock release conflict** — report, let user resolve manually.
- **Jira transition fails** — warn, continue; local cleanup still happens.

## Never do

- Never call `git worktree remove` — worktree survives until post-merge.
- Never transition to "Done" — only to "In Review." "Done" is reserved for
  after PR merge and should be set by GitHub/Jira automation or manually.
- Never skip the `pre-launch-auditor` gate with `--force` silently. If the
  user passes `--force`, log a loud warning and record it in the Jira
  comment so it's auditable.
