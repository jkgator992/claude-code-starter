# /ticket-start

Starts work on a Jira ticket. Creates a new git worktree, writes the ticket
context file, acquires any needed locks, transitions the Jira ticket to
"In Progress," and prints the command to enter the worktree.

## Usage

```
/ticket-start SCRUM-142
```

## What you (Claude) must do, step by step

### 1. Parse the ticket key

Argument is a Jira key in the form `SCRUM-NNN`. If not provided or malformed,
ask the user for it. Do not proceed without a valid key.

### 2. Fetch the Jira ticket

Use the Atlassian Rovo `fetch` or `search` tool (cloud ID:
`<FILL IN — your Jira cloud ID>`). Pull:
- Summary (title)
- Description (full)
- Status (current transition state)
- Issue type (Task, Story, Feature, Bug)
- Linked issues (blocks / is blocked by)
- Labels

If the ticket is already "In Progress" or "In Review," STOP and tell the
user. Someone (or they) is already working on it.

### 3. Parse ticket body for structured sections

Look for the following markdown sections in the description:

- `## Spec references` — list of spec file paths with section anchors
- `## Files touched` — `write:` and `read-only:` subsections with paths/globs
- `## Integration dependencies` — Blocks / Blocked by list
- `## Test cases` — test IDs from `docs/tests/test-registry.csv`

If ANY of these sections is missing:
- Offer to draft the missing sections based on the description
- Ask the user to confirm before continuing
- Do NOT proceed with missing write paths — overlap detection depends on them

### 4. Check coordination state

Locate the shared coordination directory:
```bash
COORD="$(git rev-parse --git-common-dir)/../project-coordination"
mkdir -p "$COORD"
touch "$COORD/active-worktrees.md"
```

Read `$COORD/active-worktrees.md`. For each active entry, check:

a) **Worktree still exists** (`git worktree list` includes its path). If
   not, the entry is stale — offer to clean it.

b) **File-path overlap with this ticket's `write:` paths.** Overlap rules:
   - Two tickets with overlapping `write:` globs = BLOCK unless user
     explicitly confirms serial work
   - One ticket's `write:` overlapping another's `read-only:` = OK with a
     warning
   - No overlap = safe to parallelize

If overlap blocks, list the conflicting ticket and paths. Stop.

### 5. Check migration lock (if ticket touches migrations)

If `write:` paths include `supabase/migrations/**`:

```bash
LOCK="$COORD/migration-lock"
if [ -f "$LOCK" ]; then
  HOLDER=$(head -n1 "$LOCK")
  AGE_HOURS=$(( ( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK") ) / 3600 ))
  if [ "$HOLDER" != "SCRUM-NNN" ] && [ $AGE_HOURS -lt 4 ]; then
    # Block — another ticket holds the lock
    echo "Migration lock held by $HOLDER (age: ${AGE_HOURS}h)"
    exit 1
  fi
fi
# Acquire lock
echo "SCRUM-NNN" > "$LOCK"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOCK"
```

If the lock is held by another ticket younger than 4 hours, BLOCK. Tell the
user to either wait, coordinate with the holder, or force-release (with
confirmation) if the holder is known-complete.

If the lock is held and older than 4 hours, offer to force-release after
confirming the holder worktree is idle (`git worktree list` + user confirm).

### 6. Create the worktree

```bash
WORKTREE_DIR="../<PROJECT_SLUG>-${TICKET_KEY}"
BRANCH="feature/${TICKET_KEY}-${SLUG}"
# SLUG = lowercased, dash-separated first 4 words of ticket summary

git worktree add "$WORKTREE_DIR" -b "$BRANCH"
```

If the branch already exists, switch to using it instead of creating.

### 7. Write `docs/current-ticket.md` inside the new worktree

Template:

```markdown
# SCRUM-NNN — <Summary>

**Status:** In Progress
**Branch:** <branch>
**Worktree:** <path>
**Started:** <iso-timestamp>
**Jira:** https://<FILL IN — your Atlassian site>/browse/SCRUM-NNN

## Description
<full description from Jira>

## Acceptance criteria
<bullets>

## Spec references
<list>

## Files touched
write:
<list>
read-only:
<list>

## Integration dependencies
Blocks: <list>
Blocked by: <list>

## Test cases
<list from test-registry.csv>

## Dispatch playbook

This ticket is managed by the `dispatcher` agent. Expected workflow:

1. **Phase 1 — Planning** (now): run `dispatcher` via "dispatch" keyword.
   It will call `architect` to produce an implementation plan against the
   spec refs above.
2. **Phase 2 — Implementation**: main session implements plan. No dispatcher
   during this phase.
3. **Phase 3 — Review** (before every commit): run "review before commit."
   Dispatcher runs `layer1-enforcer`, `security`, `rls-auditor`, `qa-tester`
   in parallel against the staged diff.
4. **Phase 4 — Pre-merge** (before PR open): run "pre-PR audit." Dispatcher
   runs `pre-launch-auditor` Tier 1 and verifies traceability.

Commit pattern: `<type>(SCRUM-NNN): <subject>` — e.g., `feat(SCRUM-142): add
proximity check to redemption create`.

## Locks held
<"migration-lock" if acquired in step 5, else "none">

## Opened by
/ticket-start at <iso-timestamp>
```

### 8. Update `$COORD/active-worktrees.md`

Append a new entry. Format:

```
SCRUM-NNN | ../<PROJECT_SLUG>-SCRUM-NNN | feature/SCRUM-NNN-slug | started: <iso> | write: <comma-separated globs> | locks: <migration-lock if held>
```

### 9. Transition the Jira ticket to "In Progress"

Get transitions via `getTransitionsForJiraIssue`, find the one named
"In Progress" (may be called "Start" or similar), transition via the
Atlassian API. Add a comment on the ticket:

> Worktree started: `../<PROJECT_SLUG>-SCRUM-NNN`, branch `feature/SCRUM-NNN-slug`.
> Opened by Claude Code via /ticket-start at <iso-timestamp>.

If the transition fails (permission, workflow config), warn but continue —
the worktree is still usable.

### 10. Install dependencies in the new worktree

Detect the package manager by lockfile and run install. This keeps the
user from hitting `tsc: command not found` (or similar) on their first
commit in the fresh worktree.

```bash
if [[ -f "$WORKTREE_DIR/pnpm-lock.yaml" ]]; then
  pm="pnpm"
elif [[ -f "$WORKTREE_DIR/yarn.lock" ]]; then
  pm="yarn"
elif [[ -f "$WORKTREE_DIR/package-lock.json" ]]; then
  pm="npm"
else
  pm=""
fi

if [[ -n "$pm" ]]; then
  echo "Installing dependencies via $pm..."
  (cd "$WORKTREE_DIR" && "$pm" install) || {
    echo "WARNING: $pm install failed. You may need to run it manually before your first commit."
  }
else
  echo "No lockfile detected — skipping dependency install."
fi
```

If install fails, warn the user in the final summary but do not roll back
the worktree — the user can run install manually after diagnosing.

### 11. Print instructions for the user

Final output block:

```
✅ SCRUM-NNN worktree ready.

To start work:
  cd ../<PROJECT_SLUG>-SCRUM-NNN
  claude

Then say: "dispatch" — the dispatcher will read docs/current-ticket.md
and run Phase 1 (Planning).

Active worktrees: <count including this one>
Migration lock: <held by this ticket | held by SCRUM-XXX | free>
Dependencies: <installed via pnpm | installed via yarn | installed via npm | skipped (no lockfile) | install failed — run manually>

To close when done:
  /ticket-close SCRUM-NNN
```

## Error handling

- **Ticket not found in Jira** — stop, report.
- **Ticket already In Progress or In Review** — stop, report who/when.
- **Write-path overlap with active ticket** — stop, report conflicting
  ticket and paths, suggest serial work or alternate scope.
- **Migration lock held by other ticket, young** — stop, report holder.
- **Migration lock held, stale (>4h)** — offer force-release with
  confirmation.
- **Worktree directory already exists** — offer to reuse it (switch to its
  branch) or pick a different path.
- **Jira transition fails** — warn, continue; worktree is still usable.
- **`git worktree add` fails** — roll back: remove any coord entry added,
  release migration-lock if acquired, report error.

## Edge cases

- **Subtasks**: if ticket is a Subtask, also note its parent in
  `current-ticket.md` so the dispatcher can surface parent-level spec refs.
- **Bug tickets without spec refs**: ask user to supply or skip Phase 1
  planning.
- **Tickets with `write:` of `docs/**` only** (doc-only work): skip migration
  lock, run dispatcher in a lightweight mode (no review phase needed).
- **Re-running on the same ticket**: if worktree and branch exist and
  current-ticket.md is present, report "already started at <timestamp>"
  and print the cd instruction without recreating.

## Never do

- Never create a worktree without updating `active-worktrees.md` — that
  breaks overlap detection for all future tickets.
- Never acquire the migration lock silently — always show the user you're
  taking it.
- Never transition a Jira ticket to "In Progress" if the worktree creation
  failed — keep Jira in sync with reality.
- Never skip the overlap check because the user says "it's fine." The
  check exists because that assumption breaks under pressure.
