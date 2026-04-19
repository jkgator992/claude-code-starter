# /batch-plan

Reads the structured Jira backlog (after `/backfill-tickets` has run) and
outputs a wave-by-wave parallel execution plan. Each wave lists tickets that
can run concurrently. Dependencies are respected. File-path conflicts are
flagged with suggested resolutions.

This is a planning tool, not an executor. It outputs what to run; the human
picks and then calls `/ticket-start` per ticket.

## Usage

```
/batch-plan                            # plan the full open backlog
/batch-plan --label phase-7            # plan just phase-7
/batch-plan --max-parallel 3           # cap waves at 3 parallel tickets
/batch-plan --start-from SCRUM-54      # assume everything before this is done
/batch-plan --focus SCRUM-70           # plan the critical path to ship SCRUM-70
```

## What you (Claude) must do, step by step

### 1. Parse args and determine target set

- `--label <label>` — filter to one phase/area
- `--max-parallel <n>` — ceiling per wave; default 4 (your review bandwidth)
- `--start-from <ticket>` — exclude this and everything it transitively
  blocks from consideration; useful if you've already finished some work
- `--focus <ticket>` — compute only the critical path needed to unblock
  this specific ticket

### 2. Pull structured tickets

JQL: `project = SCRUM AND statusCategory != Done ORDER BY created ASC`

For each ticket, extract:

- Key, summary, priority, labels, status
- `Files touched` → `write:` and `read-only:` glob lists
- Integration dependencies from formal issue links (fetch via fields
  param including `issuelinks`)
  - "is blocked by" → hard dependency
  - "blocks" → reverse (this ticket blocks others)
  - "relates to" → soft dependency (noted, not enforced)

If a ticket lacks `Files touched`, flag it and exclude from the plan —
suggest running `/backfill-tickets --ticket <key>` first.

### 3. Build the dependency graph

Nodes = tickets. Edges = "is blocked by" links. Detect cycles and report
as errors — a cycle means your backlog has logically impossible
dependencies and must be resolved before planning.

Transitive closure: if A blocks B, and B blocks C, then A blocks C
(important for correct wave assignment).

### 4. Topological sort into waves

Wave 0 = all tickets with no unresolved dependencies (no "blocked by"
edge pointing to a still-open ticket).

Wave 1 = tickets whose dependencies are all in Wave 0.

Wave 2 = tickets whose dependencies are all in Wave 0 ∪ Wave 1.

...and so on.

### 5. Apply file-path conflict detection within each wave

Within a single wave, compute pairwise `write:` overlap:

- For each pair of tickets (A, B) in the same wave, expand globs to
  concrete prefixes and check for intersection
- If they overlap on `write:`, they CANNOT run in parallel — they must
  be split across waves or merged

For each conflict, propose a resolution:

- **Split:** move one ticket to the next wave (simple, but adds latency)
- **Serialize:** mark one as blocking the other by adding a "is blocked
  by" link (makes explicit what was implicit)
- **Combine:** suggest merging into a single ticket if scope is small
  (e.g. two tickets both editing 20 lines in the same file)
- **Refactor:** suggest extracting the shared file into a prerequisite
  ticket

Examples:

- SCRUM-59 and SCRUM-60 both write `packages/.../stripe/_shared.ts` →
  recommend extracting that file into SCRUM-70 (or whichever is earliest)
- SCRUM-64 and SCRUM-65 both write
  `packages/database/operations/redemptions/__tests__/*.test.ts` →
  recommend merging, since they're both testing the same operations

### 6. Apply `--max-parallel` cap

If a wave has more than `max_parallel` tickets, split it:

- Sort by priority (High before Medium before Low)
- Keep the top N as Wave X; push the rest to Wave X.5 (they still run
  in parallel, just after the first N complete)

Explain the split in the output: "Wave 1 capped at 4 parallel; remaining
tickets deferred to Wave 1.5."

### 7. Compute critical path and wall-clock estimate

For each ticket, estimate duration based on:

- Story points if present (default 1 day per point)
- Fallback heuristic: count `write:` paths; 1-2 = 0.5 day, 3-5 = 1 day,
  6-10 = 2 days, 10+ = flag as oversized
- Priority High = multiply by 0.8 (focus), Low = multiply by 1.2
  (drift)

Wave duration = max ticket duration within the wave (parallelism).
Total wall-clock = sum of wave durations.

### 8. Output the plan

```
═══════════════════════════════════════════════════════════════
Parallel execution plan — SCRUM backlog, phase-7
═══════════════════════════════════════════════════════════════

Scope:         24 tickets (phase-7)
Estimated:     11 days wall-clock at max_parallel=4
Critical path: SCRUM-54 → SCRUM-70 → SCRUM-59 → SCRUM-68
Conflicts:     2 resolved (see notes)

────────────────────────────────────────────────────────────────
Wave 0                                                (1 ticket)
────────────────────────────────────────────────────────────────
SERIAL — no dependencies

  SCRUM-54  BullMQ setup & queue infrastructure
            write: apps/api/workers/**, packages/.../enqueue.ts
            est:   1 day
            deps:  none

────────────────────────────────────────────────────────────────
Wave 1                                              (3 parallel)
────────────────────────────────────────────────────────────────
After SCRUM-54 merges. All three touch independent file sets.

  SCRUM-55  Stripe webhook processor
            write: apps/api/src/webhooks/stripe/**
            est:   1.5 days

  SCRUM-56  Notification dispatcher
            write: apps/api/workers/notify/**
            est:   1.5 days

  SCRUM-58  PDF + Google Places workers
            write: apps/api/workers/pdf/**, apps/api/workers/places/**
            est:   2 days

  Wave duration: 2 days (max of parallel tickets)

────────────────────────────────────────────────────────────────
Wave 2                                              (2 parallel)
────────────────────────────────────────────────────────────────
After Wave 1 merges. SCRUM-70 is the gate for the integration stories.

  SCRUM-70  Tenant integrations UI + Vault secrets
            write: supabase/migrations/**, packages/.../integrations/**,
                   apps/admin/app/settings/integrations/**,
                   .claude/hooks/**
            est:   4 days

  SCRUM-63  Image processing & Anthropic Claude
            write: packages/.../images/**, packages/.../anthropic/**
            est:   2 days
            NOTE:  soft conflict — SCRUM-63 assumes direct
                   process.env.ANTHROPIC_API_KEY. Will need rework
                   to use getIntegrationSecret from SCRUM-70.
                   Recommend: start SCRUM-63 AFTER SCRUM-70 instead
                   of in parallel, to avoid rework.

  Wave duration: 4 days (SCRUM-70 dominates)

────────────────────────────────────────────────────────────────
Wave 3                                              (4 parallel)
────────────────────────────────────────────────────────────────
After SCRUM-70 merges. All read integration config via getIntegrationSecret.

  SCRUM-59  Stripe Billing
  SCRUM-60  Stripe Connect
  SCRUM-61  Google Places
  SCRUM-62  Resend + Expo push

  Wave duration: 2 days

────────────────────────────────────────────────────────────────
Conflicts resolved during planning
────────────────────────────────────────────────────────────────

  [resolved] SCRUM-59 and SCRUM-60 both claimed to write
             packages/.../stripe/_shared.ts. Recommendation applied:
             _shared.ts is now part of SCRUM-70's write set
             (platform Stripe integration config), and SCRUM-59/60
             read-only it. No rework needed if SCRUM-70 is done first.

  [resolved] SCRUM-63 has implicit dependency on SCRUM-70 via
             process.env.ANTHROPIC_API_KEY. Moved from Wave 2 parallel
             to Wave 2 serial after SCRUM-70.

────────────────────────────────────────────────────────────────
Unresolved — flagged for human attention
────────────────────────────────────────────────────────────────

  SCRUM-XX  needs Files touched — /backfill-tickets didn't handle it.
            Run: /backfill-tickets --ticket SCRUM-XX --apply
            Or:  edit the ticket manually in Jira.

  SCRUM-YY  Wave 1 candidate but scope includes 7 directories.
            Recommend splitting into 3 tickets before executing.

────────────────────────────────────────────────────────────────
Recommended first move
────────────────────────────────────────────────────────────────

  /ticket-start SCRUM-54

  Once it merges, run /batch-plan again to recompute (dependencies
  update as tickets close).
```

### 9. Special mode: `--focus <ticket>`

Instead of planning the full backlog, compute ONLY the ancestors of
the focus ticket. Output:

```
Critical path to ship SCRUM-70:

  SCRUM-54 (1 day, no blockers — start now)
       ↓
  SCRUM-70 (4 days, blocked by SCRUM-54)

Total: 5 days wall-clock (no parallelism possible on this path).

NOT on this path (can run in parallel with critical path):
  SCRUM-55, 56, 58, 63 (Wave 1 + Wave 2 non-critical)

If you start those in parallel with SCRUM-54, Wave 2 completes at
the same time SCRUM-70 finishes (day 5).
```

This is the right mode when you know what you're shipping next and just
want to sequence around it.

### 10. Re-running

The plan is ephemeral. Every run recomputes from the current state of
Jira. After completing a ticket and running `/ticket-close`, re-run
`/batch-plan` to see the updated plan.

## Reading the output

- **Bold conflicts or deferrals** — these are the moments where the
  plan made a tradeoff. Read them; they may suggest ticket restructuring
  that saves more time than following the plan literally.
- **Wave duration** = max of tickets in the wave, not sum. Wave 1 with
  three 1.5-day tickets finishes in 1.5 days, not 4.5.
- **Critical path** = the sequence that must be serial end-to-end.
  Reducing this sequence is the only way to ship faster.

## Limitations

- **Estimates are rough.** Use story points in Jira if you want tighter
  numbers; otherwise expect ±30% variance.
- **Glob-to-path expansion is heuristic.** A ticket claiming
  `apps/web/app/**` is effectively a wildcard; the planner can't know
  which sub-directory it actually touches. Be specific in `Files touched`.
- **Soft conflicts (read-only vs write)** are reported as warnings, not
  blockers. Sometimes two tickets reading each other's write paths is
  fine; sometimes it's a subtle ordering bug. Planner can't distinguish
  — you decide.
- **Doesn't account for human factors.** Timezone overlap with
  teammates, review bandwidth, cognitive load across parallel sessions
  — these are your call.

## What this is NOT

- Not a scheduler. Doesn't book time on a calendar.
- Not a commitment tool. Doesn't change Jira sprint assignment.
- Not a merge automation. You still review and merge PRs manually.
- Not a replacement for architect review on large tickets.

## Integration with the rest of the system

- Reads from Jira (already structured by `/backfill-tickets`)
- Reads from `.claude/coordination/active-worktrees.md` (in-flight work
  excluded from the plan — no point planning to start a ticket that's
  already started)
- Outputs recommendations the human acts on via `/ticket-start`
- No Jira writes. Pure read + analysis.

## Safety

- Rate limits the same as `/backfill-tickets` — 10 API calls per 5s.
- Read-only toward Jira. No mutations.
- If Jira is unavailable, falls back to cached data in
  `.claude/coordination/last-plan.json` (cached on every successful
  run) with a clear "stale by {N} minutes" warning.
