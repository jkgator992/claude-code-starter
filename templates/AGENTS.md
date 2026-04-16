# {{PROJECT_NAME}} — Agent Instructions

## Start Here

Read the `AGENTS.md` or `CLAUDE.md` in the specific directory you are
working in. Each one should link to exactly the docs and gotchas
relevant to that context.

Do not read all docs — read only what's relevant to your task.

## Project Summary

**{{PROJECT_NAME}}** — {{PROJECT_DESC}}

<!-- TODO: expand with the user-facing surfaces and backend services.
     Example:
     - Consumer web app (Next.js)
     - Admin dashboard (Next.js)
     - API workers (Node.js)
     - Database: Postgres with RLS
-->

## Architecture

<!-- TODO: describe your layer model in 3-5 lines. Example:

**LAYER 1:** packages/database/operations/
The ONLY code that calls the database directly.

**LAYER 2:** apps/api/routes/
Thin HTTP wrappers. No business logic.

**LAYER 3:** packages/ui/workflows/
Shared React components. Never call the database directly.
-->

## Non-Negotiable Rules

<!-- TODO: list the rules that must never be broken. Examples:

1. Database writes ONLY in the data-access layer.
2. Service/admin credentials ONLY in server-side code.
3. EVERY mutation writes to the audit log.
4. EVERY table has RLS — never disable.
5. Schema changes via migrations ONLY.
6. Stripe/webhook handlers verify signatures before processing.
7. Background workers have error + failed handlers.
8. No admin credentials in any client bundle.
-->

## Business Rules

<!-- TODO: list domain-specific rules here.
     See also: CLAUDE.md "Critical Business Rules" section.
-->

## Gotchas By Area

- All gotchas: [docs/gotchas.md](./docs/gotchas.md)

<!-- TODO: add anchored links to specific sections as they grow:

- Schema/DB issues: [docs/gotchas.md#schema-database](./docs/gotchas.md#schema-database)
- Auth/RLS issues: [docs/gotchas.md#auth-rls](./docs/gotchas.md#auth-rls)
- Framework-specific: [docs/gotchas.md#framework](./docs/gotchas.md#framework)
- Testing: [docs/gotchas.md#testing](./docs/gotchas.md#testing)
-->

## Commands

```bash
{{PKG_MGR}} install

# TODO: list your typecheck, test, and dev commands
# e.g.
# {{PKG_MGR}} run typecheck
# {{PKG_MGR}} run test
# {{PKG_MGR}} run dev
```

## Test Registry

- `docs/tests/test-registry.csv` — all test cases
- `docs/tests/test-results.csv` — run results

## Agent Roster

These agents live in `.claude/agents/`. Use them via the Task tool.

<!-- TODO: trim this list to match the agents you actually installed.
     Universal agents (always useful):

- `architect` — architectural decisions, designing new features before coding
- `security` — security audit of any change before it ships
- `qa-tester` — verify behavior across all actor types; propose fixes
- `qa-automation` — execute test registry, write results
- `devops` — deployment, infra, secrets, rollback

     Supabase-specific (if applicable):

- `rls-auditor` — RLS policy correctness for all actor types
- `layer1-enforcer` — verify data-access layer compliance

     Framework-specific:

- `frontend` — Next.js web app work
- `mobile-maestro` — React Native + Expo
- `backend-architect` — Node.js APIs, BullMQ, webhook pipelines
-->
