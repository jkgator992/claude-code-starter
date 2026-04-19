# Jira ticket template — parallel dev

Paste this structure into every Jira ticket's **Description** field. The
`/ticket-start` command parses these sections. Missing sections will prompt
you to fill them in before the worktree is created.

---

## Description

<What needs to be built. Plain-English. Link to any Figma, Loom, or slack
threads.>

## Acceptance criteria

- [ ] <specific, testable outcome>
- [ ] <specific, testable outcome>
- [ ] <specific, testable outcome>

## Spec references

<Paths into `docs/specs/` with section anchors. The architect agent reads
these during Phase 1 planning. At least one required.>

- docs/specs/schema/05-offers-events.md §3 (Redemptions)
- docs/specs/shared-workflows.md §redemption

## Files touched

<Critical for overlap detection. Two tickets with overlapping `write:` paths
cannot run in parallel.>

**write:**
- packages/database/operations/redemptions/createRedemption.ts
- supabase/migrations/20260XXX_add_proximity_check.sql
- apps/api/src/routes/redemptions/create.ts

**read-only:**
- packages/database/operations/offers/
- docs/specs/schema/05-offers-events.md

<Use globs where appropriate: `packages/database/operations/redemptions/**`.
If the ticket touches a migration, include `supabase/migrations/**` — this
triggers the migration-lock acquisition.>

## Integration dependencies

**Blocks:** <tickets that can't start until this one is in review>
- SCRUM-150 (mobile UI depends on this endpoint)

**Blocked by:** <tickets that must merge before this one can start>
- SCRUM-138 (needs offers.proximity_required field, adds it in a migration)

<If this section is non-empty, /ticket-start will refuse to start if any
"Blocked by" ticket is not yet "In Review" or "Done".>

## Test cases

<Test IDs from `docs/tests/test-registry.csv`. The qa-tester agent verifies
these exist and pass. At least one required.>

- redemptions.create.success.consumer
- redemptions.create.proximity_fail.consumer
- redemptions.create.expired_offer.consumer
- rls.redemptions.anon_cannot_create
- rls.redemptions.consumer_own_only

## Out of scope

<Optional. List anything the reader might assume is included but isn't.
Helps the architect agent not over-plan.>

- Push notification on successful redemption (separate ticket)
- Admin dashboard view (separate ticket)

---

## Template validation checklist

Before clicking "Create" in Jira, verify:

- [ ] Description is specific enough that someone else could implement it
- [ ] Acceptance criteria are testable (not "works well," but "returns 200
  with `{ redemption_id }` when user is within 1000m of location")
- [ ] Spec refs point to actual existing sections
- [ ] `write:` paths include ALL files this ticket will create or modify
- [ ] `write:` does NOT include files the ticket only reads — that goes in
  `read-only:`
- [ ] If migrations are involved, `supabase/migrations/**` is in `write:`
- [ ] Integration dependencies are accurate (better to over-declare than
  under-declare)
- [ ] Test cases exist in `docs/tests/test-registry.csv` or are noted as
  "to be added" with the qa-tester agent

---

## Why this structure matters

Without `write:` paths, /ticket-start can't detect overlap — you'll get
merge conflicts that waste hours.

Without spec refs, the architect agent guesses — you'll get plans that
contradict your actual schema.

Without test cases, the qa-tester agent can't verify coverage — you'll
ship regressions.

Without dependencies declared, you'll start ticket B before ticket A
merges, realize B needs A's migration, and burn the worktree.

**Every minute spent filling this out saves an hour of rework.**
