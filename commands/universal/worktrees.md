# /worktrees

Status command. Lists all active worktrees, who holds the migration lock,
and flags any stale or inconsistent entries.

## Usage

```
/worktrees           # list active, print summary
/worktrees --clean   # offer to remove stale entries
```

## What you (Claude) must do

### 1. Locate coordination state

```bash
COORD="$(git rev-parse --git-common-dir)/../project-coordination"
ACTIVE="$COORD/active-worktrees.md"
LOCK="$COORD/migration-lock"
```

### 2. Cross-reference with actual git worktrees

```bash
git worktree list --porcelain
```

For each entry in `active-worktrees.md`:
- If the worktree path exists in `git worktree list` output → **healthy**
- If not → **stale** (worktree was deleted but entry wasn't cleaned)

For each entry in `git worktree list` that's NOT in `active-worktrees.md`:
- If path matches `*<PROJECT_SLUG>-<TICKET_PREFIX>-*` → **orphan** (created outside
  /ticket-start or entry was lost)
- Otherwise → ignore (main worktree, unrelated)

### 3. Check migration-lock age

```bash
if [ -f "$LOCK" ]; then
  HOLDER=$(head -n1 "$LOCK")
  TIMESTAMP=$(sed -n '2p' "$LOCK")
  # Age in hours
fi
```

Flag if:
- Lock holder is not in active-worktrees.md → **zombie lock**
- Lock age > 4 hours → **stale lock**

### 4. Print the report

```
## Active worktrees

| Ticket    | Path                    | Branch                        | Age  | Lock | Status  |
|-----------|-------------------------|-------------------------------|------|------|---------|
| SCRUM-142 | ../<PROJECT_SLUG>-SCRUM-142       | feature/SCRUM-142-campaigns   | 2h   | ●    | healthy |
| SCRUM-143 | ../<PROJECT_SLUG>-SCRUM-143       | feature/SCRUM-143-api         | 1h   | —    | healthy |
| SCRUM-138 | ../<PROJECT_SLUG>-SCRUM-138       | feature/SCRUM-138-ui          | 9h   | —    | stale   |

● = holds migration-lock

## Migration lock
Holder:  SCRUM-142
Age:     2h 14m
Status:  healthy

## Issues
- SCRUM-138: worktree older than 8h with no recent commits — investigate or close.
- Orphan worktree found at ../<PROJECT_SLUG>-scratch — not in active-worktrees.md.

## Summary
3 active worktrees, 1 holds migration-lock, 1 stale entry.
```

### 5. If `--clean` was passed

For each stale entry, ask:
> SCRUM-138 worktree no longer exists. Remove from active-worktrees.md? [y/N]

For each zombie lock, ask:
> migration-lock held by SCRUM-XXX but that ticket has no worktree. Release? [y/N]

Do NOT auto-remove anything without confirmation.

## Never do

- Never auto-release a migration lock younger than 4 hours, even with
  `--clean`.
- Never modify a worktree that's not in `active-worktrees.md` — it might
  be the user's scratchpad or the main checkout.
- Never report a worktree as healthy if its branch has been deleted from
  origin — that's usually a sign someone merged without using
  `/ticket-close`.
