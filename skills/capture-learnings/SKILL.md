---
name: capture-learnings
description: Use when recording a gotcha, lesson, or TODO that future sessions should reference. Explains both the auto-capture path (via `// GOTCHA:` comments) and the manual path (edit `docs/gotchas.md` directly).
---

# Capture Learnings Skill

How to record a gotcha, lesson, or TODO for the team.

## Automatic Capture (via hooks)

The `capture-gotcha.sh` hook automatically captures:

- `// GOTCHA:` comments → `docs/gotchas.md`
- `// BUG:` comments → `docs/gotchas.md`
- `// WARN:` comments → `docs/gotchas.md`
- `// TODO:` comments → `docs/todos.md`

Supported comment markers: `//` (TS/JS), `--` (SQL), `#` (Python, shell, Ruby).

Just write the comment in your code and the hook fires on save.

## Manual Capture

To add a gotcha manually to `docs/gotchas.md`:

1. Identify the correct section using its `<!-- anchor: ... -->` marker.
   Default sections:
   - Schema & Database → `#schema-database`
   - Auth & RLS → `#auth-rls`
   - React Native & Expo → `#react-native-expo`
   - Next.js & API → `#nextjs-api`
   - Stripe & Payments → `#stripe-payments`
   - BullMQ & Workers → `#bullmq-workers`
   - Testing → `#testing`
   - General → `#general`

2. Add a bullet in the correct section:
   - **[YYYY-MM-DD]** `path/to/file`: What happened and what to do instead.

## Format Examples

Good gotcha entry:

- **[2026-04-16]** `supabase/migrations/`: `now()` is STABLE not
  IMMUTABLE — cannot use in index predicates. Use plain partial index
  without time comparison.

Good TODO entry:

- [ ] [2026-04-16] `packages/database/operations/`: Add retroactive
      fundraiser credit logic when a new offer is created.

## References

- `docs/gotchas.md` (the knowledge base)
- `docs/todos.md` (the TODO list)
- `.claude/hooks/capture-gotcha.sh` (automatic capture)
