# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project

**{{PROJECT_NAME}}** — {{PROJECT_DESC}}

<!-- TODO: expand the project description above. What are the user-facing
     surfaces? Who are the actors? What is the business domain? -->

## Before Writing Any Code

Read the CLAUDE.md in the specific subdirectory you are working in. Each
one should point to the exact docs, gotchas, and specs relevant to that
app or package.

If no subdirectory CLAUDE.md exists, read:

- [docs/gotchas.md](./docs/gotchas.md) — accumulated lessons
- [docs/violations.md](./docs/violations.md) — open issues that block commits
- [AGENTS.md](./AGENTS.md) — agent routing rules

<!-- TODO: add paths to your architecture, spec, or ADR docs here if you
     have them. e.g. docs/specs/*, docs/architecture/*, ADRs, etc. -->

## Architecture

**Tech stack:** {{TECH_STACK}}
**Package manager:** {{PKG_MGR}}
**Test runner:** {{TEST_RUNNER}}
**Supabase:** {{USE_SUPABASE}}

<!-- TODO: replace this stub with your actual architecture.
     Sketch the layering:
       - where does data access live?
       - what's shared vs per-app?
       - what's the request/response / event flow?
     The more specific this is, the better Claude can follow your patterns.
-->

## Apps / Packages

<!-- TODO: list your top-level apps and packages. Example:

| App           | Stack                | Port | Purpose                  |
| ------------- | -------------------- | ---- | ------------------------ |
| `apps/web`    | Next.js 15           | 3000 | Customer dashboard       |
| `apps/api`    | Node.js + Express    | 8080 | Background workers       |
| `apps/mobile` | React Native + Expo  | —    | Consumer iOS + Android   |
-->

## Common commands

```bash
# install dependencies
{{PKG_MGR}} install

# dev
# TODO: list your dev commands (e.g. npm run dev, npm run dev:web)

# quality
# TODO: list typecheck, lint, test, build

# TODO: if using Supabase, list:
#   npx supabase start
#   {{PKG_MGR}} run db:reset
#   {{PKG_MGR}} run db:migrate
#   npx supabase migration new <name>
#   npx supabase gen types typescript --local > <path to database.ts>
```

## Conventions

<!-- TODO: document your non-negotiable conventions. Examples:

- Never call the database directly from app code — use the data layer.
- Schema changes go through migrations, never ad-hoc SQL.
- Every table has RLS enabled.
- Secrets split by trust boundary: which keys are server-only vs client-safe.
- Background work (emails, push, billing) is enqueued, never blocks a request.
- Shared workflows live in a shared package, not duplicated per app.
-->

## Environment

See [.env.example](./.env.example) for the full list of variables.

<!-- TODO: list Node / Python / etc. version requirements -->

## Critical Business Rules (Never Violate)

<!-- TODO: add your business rules. Claude will reference these.
     Examples from a typical SaaS:

- Subscription status: only one active per customer (partial unique index).
- Password reset tokens: 15 minute expiry, single-use.
- Webhook signatures: verified before any processing.
- Audit log: every mutation on critical entities writes a row.
-->

## Layer Rules (Non-Negotiable)

<!-- TODO: replace with your actual layer rules. Example shape:

**Layer 1 — data access (e.g. packages/database/operations/):**

- ONLY place that calls the database directly
- Pattern: validate permissions → validate input → validate business rules
  → mutate in transaction → write audit_log → emit events → return entity
- Never use admin/service credentials here

**Layer 2 — request handlers (e.g. apps/api/routes/):**

- Thin HTTP wrappers only
- No business logic — delegate everything to Layer 1

**Layer 3 — shared UI (e.g. packages/ui/workflows/):**

- Shared components, especially multi-step workflows
- Import from the data layer; never duplicate business logic
-->
