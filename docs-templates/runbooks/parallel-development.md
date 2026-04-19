# Parallel development runbook

How to ship multiple Jira tickets in parallel using Claude Code, git
worktrees, and the dispatcher agent system.

**Last drill:** never
**Review cadence:** update after every sprint for the first 3 sprints

---

## When to use this

- You have 3+ Jira tickets ready to start
- Their `write:` paths don't overlap
- None of them is blocked by another

**When NOT to use this:**

- Solo feature where sequential work is faster than coordinating
- Spike / investigation work with unclear scope
- Anything with cross-cutting schema changes that would need migration-lock
  juggling

---

## The ceiling is 3–5 sessions

More is not faster. The bottlenecks at 6+ sessions:

- **Review cost** scales linearly — you are the reviewer, not Claude
- **Merge conflicts** scale super-linearly
- **Context-switching** — every session you check in on is context you
  reload in your own head
- **Integration testing** is still serial at the end

Start with 2. Move to 3 when you're confident. 5 is the cap unless you're
doing documentation-only work.

---

## Daily workflow

### Morning: pick the batch

1. Open Jira. Look at "To Do" tickets at the top of the backlog.
2. For each candidate, check its **Files touched** section.
3. Find 2-4 whose `write:` paths don't overlap. Good batch examples:
   - One schema/migration ticket
   - One API/operations ticket (read-only on the first's migrations)
   - One mobile UI ticket (no overlap with backend)
4. Verify none of them is blocked by another in the batch.

### Start each ticket

In your main checkout (call this "terminal 0"):

```bash
cd /path/to/<PROJECT_SLUG>
/ticket-start SCRUM-142
# ... /ticket-start prints: cd ../<PROJECT_SLUG>-SCRUM-142 && claude

/ticket-start SCRUM-143
/ticket-start SCRUM-144
```

### Open one terminal per ticket

```bash
# Terminal 1
cd ../<PROJECT_SLUG>-SCRUM-142
claude
> dispatch

# Terminal 2 (new terminal window/tab)
cd ../<PROJECT_SLUG>-SCRUM-143
claude
> dispatch

# Terminal 3
cd ../<PROJECT_SLUG>-SCRUM-144
claude
> dispatch
```

Each `dispatch` call runs Phase 1 (Planning). Claude produces a plan. You
review, approve, then implement.

### Implementation (Phase 2)

Work in each terminal. Treat each as a separate focus area. Don't
context-switch between them mid-change — finish a unit of work in one
terminal before jumping to another.

### Before each commit

In the current terminal:

```
> review before commit
```

Dispatcher runs Phase 3 — layer1-enforcer, security, rls-auditor, qa-tester
in parallel. Waits ~30-60 seconds. Returns verdict.

- **SHIP** → commit with `<type>(SCRUM-NNN): <subject>`
- **BLOCK** → fix, re-run
- **CONDITIONAL** → decide whether to address or defer; commit if deferred

### Before PR open

```
> pre-PR audit
```

Dispatcher runs Phase 4 — pre-launch-auditor Tier 1. Final gate.

```bash
git push origin feature/SCRUM-142-campaigns
gh pr create --title "SCRUM-142: Add campaigns schema" --body "..."
```

Then:

```
/ticket-close SCRUM-142 --pr-url https://github.com/<YOUR_ORG>/<YOUR_REPO>/pull/321
```

This updates Jira to "In Review," writes the traceability entry, releases
the migration-lock (if held), and removes the entry from active-worktrees.

### After PR merges

From your main checkout:

```bash
git worktree remove ../<PROJECT_SLUG>-SCRUM-142
git branch -d feature/SCRUM-142-campaigns
```

---

## Monitoring the fleet

At any time, from any worktree:

```
/worktrees
```

Shows all active tickets, who holds the migration-lock, health status. Run
this whenever you feel you've lost track. Run it at end of day.

---

## Handling conflicts

### Write-path overlap

`/ticket-start` blocks before starting. Options:
- Wait for the other ticket to close
- Combine scopes into one ticket (often the right answer)
- Serialize — start the first, wait until it's in Phase 3, then start the
  second (risky; may still conflict at merge)

### Migration-lock contention

`/ticket-start` blocks. Options:
- Wait for holder to close
- Coordinate: if two migrations are small and related, combine into one
  migration file in a single ticket
- Force-release ONLY if the holder is genuinely idle:
  ```bash
  .claude/hooks/check-migration-lock.sh --force-release
  ```
  Then the other ticket can `/ticket-start` again.

### Merge conflicts at PR time

If two PRs that passed overlap checks still conflict at merge — it means
one of them touched a file not listed in its `write:` section. Next
sprint, review that ticket's template to understand what was missed.

### Reviewer requests changes

Do NOT close the worktree. Return to it:

```bash
cd ../<PROJECT_SLUG>-SCRUM-142
claude
```

Fix, `review before commit`, commit, push. PR updates. No new
/ticket-start needed.

---

## Stale state recovery

Symptoms:
- `/ticket-start` complains about an overlap with a ticket you thought was
  closed
- `migration-lock` is held by a ticket whose worktree you already deleted
- `git worktree list` shows a worktree that `/worktrees` doesn't know about

Fix:

```
/worktrees --clean
```

Confirm each prompt. If that's not enough, manual nuke:

```bash
COORD="$(git rev-parse --git-common-dir)/../project-coordination"
rm -rf "$COORD"
# Now re-run /ticket-start on any ticket you still have a live worktree for
```

---

## Failure modes to watch for

1. **Skipping /ticket-start** ("I'll just make a branch") — breaks overlap
   detection, breaks migration-lock, breaks traceability. Don't.

2. **Force-releasing the migration-lock casually** — the whole point is
   preventing schema corruption. Force-release ONLY after confirming the
   other session is truly idle.

3. **Running 5 sessions when you have 3 hours of review bandwidth** — you
   become the bottleneck. PRs pile up unreviewed, context decays, merges
   get messier.

4. **Skipping `pre-PR audit`** — Tier 1 catches things at cost pennies
   that cost hours to fix in review.

5. **Not updating `docs/current-ticket.md`** if scope changes mid-work —
   the file is the source of truth for the dispatcher. If it's stale,
   dispatcher reviews against wrong criteria.

6. **Editing files outside the worktree's `write:` list** — catches you at
   merge time, not commit time. Worst class of failure. Prevent by keeping
   tickets narrow.

---

## First-week ramp

Week 1: 2 parallel tickets max. Get comfortable with /ticket-start,
dispatcher, /ticket-close.

Week 2: Try 3. Watch for overlap at merge. Review `/worktrees` output
daily.

Week 3: Add migration-heavy tickets to the mix. Test migration-lock
contention on purpose once, see how it feels to be blocked.

Week 4+: Steady-state at 3-4 parallel. Revisit this runbook if anything
recurs.

---

## Drills

Run these once before relying on the system in earnest.

**Drill 1: overlap detection.**
Create two test tickets with overlapping `write:` paths. Run /ticket-start
on both. Verify the second is blocked with a clear message.

**Drill 2: migration-lock contention.**
Two tickets, both touch `supabase/migrations/**`. Verify lock is acquired
by the first and the second is blocked.

**Drill 3: force-release recovery.**
Acquire the migration-lock on one ticket. Close its worktree without
`/ticket-close`. Verify `/worktrees` flags the zombie lock. Force-release.
Verify the next ticket can acquire.

**Drill 4: full round-trip.**
Start, dispatch, implement (trivially), review, audit, close, merge, clean
up. Time it. Note anything that felt slow or confusing — that's the next
improvement target.
