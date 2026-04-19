# /backfill-tickets

One-shot backfill that walks the open Jira backlog and augments each ticket
with the structured sections required by the parallel dev system: `Files
touched`, `Test cases`, and formal Jira issue links for dependencies currently
only expressed in prose ("per Story 40", "Story 22 producer", etc.).

This is designed to be run ONCE after installing the parallel dev system,
against an existing backlog that wasn't written to the template. After this
runs, `/batch-plan` and `/ticket-start` work against the real backlog.

## Usage

```
/backfill-tickets --dry-run              # default; shows proposed changes, applies nothing
/backfill-tickets --apply                # actually write changes to Jira
/backfill-tickets --apply --label phase-7 # only phase-7 tickets
/backfill-tickets --apply --ticket SCRUM-59  # only one ticket, useful for iterating
```

Always start with `--dry-run`. Review the diff. Then `--apply`.

## What it does

For every ticket in the target set, in this order:

1. **Parse existing description** — extract spec references, prose dependency
   mentions ("Story N", "per Story N"), acceptance criteria, priority labels.
2. **Infer `Files touched`** — based on spec refs and your three-layer
   conventions (see Inference Rules below).
3. **Infer `Test cases`** — cross-reference with `docs/tests/test-registry.csv`
   to find existing test IDs in the same domain; propose new ones where gaps
   exist.
4. **Detect dependencies** — scan prose for "Story N" / "SCRUM-N" mentions;
   determine whether each is `Blocks` or `Is Blocked By` based on phrasing
   ("needs", "depends on", "after", "before", "per" all indicate direction).
5. **Produce a diff** — show what would change per ticket.
6. **On `--apply`:**
   - Update each ticket's description with appended structured sections
   - Create formal Jira issue links via `createIssueLink`
   - Add a comment on each ticket: "Structured sections added by
     /backfill-tickets at {timestamp}. Review and edit as needed."

## What you (Claude) must do, step by step

### 1. Parse args and determine target set

- `--dry-run` vs `--apply` — the single most important switch. Default to
  dry-run. NEVER apply without explicit `--apply` flag.
- `--label <label>` — filter JQL to `project = SCRUM AND labels = "{label}"
  AND statusCategory != Done`
- `--ticket <key>` — filter to one ticket
- No filter + `--apply` means "backfill the entire backlog" — require an
  extra confirmation prompt showing the count before proceeding

### 2. Pull the target tickets

Use `searchJiraIssuesUsingJql` with cloud ID
`<FILL IN — your Jira cloud ID>`. Fields needed:

- summary, description, status, issuetype, priority, labels, created
- Pagination: Jira returns up to 100 per page; loop until no
  `nextPageToken`

### 3. Build the project conventions map (read once, in memory)

Before processing tickets, read these files from the repo to ground
inferences:

- `docs/specs/schema/00-conventions.md` — naming patterns for operations,
  migrations, tests
- `docs/specs/schema/01-10-*.md` — section-to-path mappings
- `docs/specs/shared-workflows.md` §7 — operation catalog (every numbered
  op maps to a file path)
- `docs/tests/test-registry.csv` — existing test IDs for cross-reference
- `packages/database/operations/` directory listing — actual existing
  operation files
- `supabase/migrations/` directory listing — next available migration
  number

Build in-memory maps:

- `spec_section_to_paths`: for each `docs/specs/schema/NN-*.md §K`, which
  migration files, operation directories, API route directories, and UI
  component directories that section implicates
- `operation_number_to_file`: maps "Story 16" style numeric references
  into `packages/database/operations/{domain}/{name}.ts`
- `existing_test_ids_by_domain`: for every domain (auth, redemptions,
  offers, etc.), which test IDs already exist in `test-registry.csv`

### 4. For each ticket, infer `Files touched`

Apply these rules in order, accumulating paths:

**Rule A — Spec section inference.** If description says `spec:
docs/specs/schema/05-offers-events.md §7`, consult `spec_section_to_paths`.
That section maps to:
- migration glob: `supabase/migrations/**_offers_events*.sql`
- operations glob: `packages/database/operations/offers/**`
- API routes: `apps/api/src/routes/offers/**`
- tests: `packages/database/operations/offers/__tests__/**`

**Rule B — Operation number mapping.** Scan description for numeric
"Story N" / "Op N" references. Map to concrete operation file via the
catalog (e.g., "Story 16" → `initiateRedemption.ts`). Add to `write:` if
this ticket is implementing the op; add to `read-only:` if it's
referenced but not implemented.

**Rule C — Layer-keyword mapping.** Scan for keywords and add
corresponding globs:

| Keyword in description            | Adds to write                                    |
|-----------------------------------|--------------------------------------------------|
| "BullMQ", "worker", "queue"       | `apps/api/workers/**`, `apps/api/src/queues/**`  |
| "webhook"                         | `apps/api/src/webhooks/**`                       |
| "cron", "scheduled"               | `apps/api/src/cron/**`                           |
| "dashboard" (business)            | `apps/web/app/**`                                |
| "dashboard" (admin), "staff"      | `apps/admin/app/**`                              |
| "mobile", "screen", "Expo"        | `apps/mobile/app/**`                             |
| "workflow" + "shared"             | `packages/ui/components/workflows/**`            |
| "migration", "schema", table name | `supabase/migrations/**`                         |
| ".env.example", "secret", "key"   | `.env.example`                                   |

**Rule D — Description-explicit files.** Description may name files
directly (`apps/api/workers/pdf-generate.ts`). Extract and add verbatim.

**Rule E — Test file mirroring.** For every operation file added to
`write:`, add the corresponding `__tests__/{file}.test.ts` to `write:`
too.

**Rule F — Type regeneration marker.** If any migration is added to
`write:`, add `packages/shared/types/src/database.ts` to `read-only:`
with a comment `(regenerated, not hand-edited)`.

**Deduplicate.** If the same path is inferred from multiple rules, keep
once. If the same glob is both `write:` and `read-only:`, keep `write:`.

**Flag for manual review.** If fewer than 2 write paths inferred, or
description contains "refactor", "multiple", "general", "all", or spans
more than 4 distinct top-level directories, mark the ticket as
`needs_human_review` and include a note: "Auto-inference uncertain.
Review suggested paths and tighten scope if possible."

### 5. For each ticket, infer `Test cases`

Build the test case list by:

- **Existing tests for the domain** — include those already in
  `test-registry.csv` that match the ticket's domain and are currently
  `status='pending'`
- **New tests from acceptance criteria** — for each acceptance criterion,
  propose a test ID in the format
  `{domain}.{feature}.{scenario}.{actor_type}`
- **Required RLS tests** — every ticket touching a new table MUST have
  four RLS test cases (anon blocked, consumer scoped, business scoped,
  staff cross-tenant)
- **Required actor-type tests** — every Layer 1 operation MUST have
  consumer/business/staff happy-path tests per `shared-workflows.md` §10

Cap at 15 test cases per ticket — beyond that, the ticket is too broad.

### 6. For each ticket, detect dependencies

Scan description for patterns:

- `"Story N"`, `"story N"`, `"SCRUM-N"` — each is a candidate link
- Phrasing to determine direction:
  - **Is Blocked By:** "needs", "depends on", "after", "requires", "uses
    infra from", "per Story N producer"
  - **Blocks:** "enables", "before", "consumed by"
  - **Relates:** "see also", "parallel to", neutral mention
- Double-check by fetching the referenced ticket and checking its own
  description for a reverse reference — if it exists with the opposite
  direction, the link is confirmed

For each detected link, propose:

```
SCRUM-65 "Is Blocked By" SCRUM-54    (phrase: "uses BullMQ infra from Story 40")
SCRUM-65 "Is Blocked By" SCRUM-59    (phrase: "Stripe subscription test dependency")
```

**Skip** links that already exist as formal Jira links (check via the
issue's existing `issuelinks` field). No duplicates.

### 7. Produce the diff report

For `--dry-run`, output per ticket:

```
═══════════════════════════════════════════════════════════════
SCRUM-65 — Integration tests — critical flows
═══════════════════════════════════════════════════════════════

STATUS: ready_to_apply (or needs_human_review with reason)

PROPOSED — append to description:

## Files touched
write:
  - apps/api/__tests__/integration/**
  - docs/tests/test-registry.csv
  - docs/tests/test-results.csv
read-only:
  - packages/database/operations/**
  - docs/specs/shared-workflows.md
  - (regenerated, not hand-edited) packages/shared/types/src/database.ts

## Test cases
Existing (pending):
  - redemptions.create.success.consumer
  - redemptions.create.proximity_fail.consumer
  - donations.create.success.consumer
  - subscriptions.create.success.business
Proposed (new):
  - integration.flow.business_onboarding_to_redemption.full
  - integration.flow.fundraiser_lifecycle.full
  - integration.flow.subscription_lifecycle.full
  - integration.flow.impersonation_audit.full

PROPOSED — create issue links:
  SCRUM-65 "Is Blocked By" SCRUM-54 (phrase: "BullMQ in IN_MEMORY mode")
  SCRUM-65 "Is Blocked By" SCRUM-59 (phrase: "Stripe test webhooks")
  SCRUM-65 "Relates to"    SCRUM-64 (phrase: "operation tests from")

AUTO-INFERENCE CONFIDENCE: high
```

### 8. On `--apply`, execute changes

For each ticket marked `ready_to_apply`:

1. Fetch current description (avoid stale overwrites)
2. Append the new sections to the description in markdown
3. Call `editJiraIssue` with the new description
4. For each proposed link, call `createIssueLink`
5. Add a comment: "Structured sections added by /backfill-tickets at
   {timestamp}. Review and edit as needed."

Use rate limiting — no more than 10 Jira API calls per 5 seconds to
avoid throttling. Wait and retry on 429.

For each ticket marked `needs_human_review`, skip the apply, but still
add a comment: "/backfill-tickets skipped this ticket — manual
structuring needed. Reason: {reason}."

### 9. Report

Final output:

```
Backfill complete.

  68 tickets processed
  51 auto-applied
  11 needs_human_review (see list below)
   6 already had all sections, skipped

Total Jira writes:  102 description updates + 147 issue links + 62 comments
Total API calls:    311
Throttling events:  3 (auto-retried)

Tickets flagged for human review:
  SCRUM-XX: scope too broad (7 directories inferred)
  SCRUM-YY: description contains "refactor" keyword
  ...

Next step: run /batch-plan to see parallel execution waves based on the
newly-structured backlog.
```

## Safety rules

- **NEVER apply without `--apply`.** Default is dry-run.
- **NEVER delete existing sections.** Backfill only appends structured
  sections; existing description content is preserved intact.
- **NEVER overwrite an existing `## Files touched` or `## Test cases`
  section** — if the human already wrote one, skip that section and
  flag the ticket for review.
- **NEVER create a link that already exists formally** — check existing
  `issuelinks` first.
- **NEVER run on tickets in status Done** — JQL filter excludes these.
- **Batch limit**: if target set exceeds 200 tickets, require a second
  confirmation — at that size, human review time dominates and the
  filter should probably be narrower (e.g. one phase at a time).

## Error handling

- **Jira API 403** — user lacks permission to edit; report per-ticket and
  continue
- **Jira API 429** — back off 10s, retry up to 3 times
- **Spec file missing** — can't ground inference, mark entire run as
  `blocked` and report missing file
- **Inference produces zero `write:` paths** — always flag as
  `needs_human_review`; never apply empty file list
- **Link creation for non-existent ticket** — skip that link, log a
  warning

## What this does NOT do

- Does not split oversized tickets. Flags them. Human decides.
- Does not change priorities, labels, assignees, sprints, or status.
- Does not transition tickets. "To Do" stays "To Do."
- Does not modify the project description, epic descriptions, or
  sprint descriptions. Only touches individual issue descriptions.
- Does not touch closed / Done tickets.
- Does not set estimates or story points.

## After it runs

Three things happen next:

1. Review the flagged tickets. Split or tighten scope on each.
2. For any ticket you want to restructure entirely, edit directly in
   Jira — backfill won't touch it again if you re-run.
3. Run `/batch-plan` to see what the newly-structured backlog looks
   like in terms of parallel execution.

## Re-running

Safe to re-run. The command skips tickets that already have the
structured sections. Useful after you split oversized tickets — just
run it again to backfill the new children.
