# Development Gotchas & Lessons Learned

Auto-populated by hooks. Add entries manually or via `// GOTCHA:` /
`-- GOTCHA:` / `# GOTCHA:` comments in your code.

## Schema & Database

<!-- anchor: schema-database -->

- **Supabase type identity drift.** Any package importing
  `SupabaseClient<Database>` must use `moduleResolution: "NodeNext"`
  (or `"Bundler"`) in its `tsconfig.json`. Mixed settings cause
  TypeScript to see two structurally-identical-but-distinct versions
  of the same type, producing an error like:

      Argument of type 'SupabaseClient<Database, ...>' is not
      assignable to parameter of type 'SupabaseClient<Database, ...>'.
        Type 'Database' is not assignable to type 'Database'. Two
        different types with this name exist, but they are unrelated.

  Root cause: `@supabase/supabase-js` v2 publishes ESM-first types
  that resolve differently under `Node` vs `NodeNext` moduleResolution.
  Fix: set `moduleResolution: "NodeNext"` (and `module: "NodeNext"`)
  in the offending tsconfig. Applied repo-wide in Oobi during SCRUM-54
  to packages/database/operations/tsconfig.json.

## Auth & RLS

<!-- anchor: auth-rls -->

## React Native & Expo

<!-- anchor: react-native-expo -->

## Next.js & API Routes

<!-- anchor: nextjs-api -->

## Stripe & Payments

<!-- anchor: stripe-payments -->

## BullMQ & Workers

<!-- anchor: bullmq-workers -->

## Testing

<!-- anchor: testing -->

## Parallel Development

<!-- anchor: parallel-dev -->

- **Terminal commits vs. Claude Code commits.** As of starter v0.2.2,
  parallel-dev installs a lightweight `.git/hooks/pre-commit` shim that
  runs the migration-lock check on every git commit (terminal or
  Claude Code). This closes the terminal-commit gap. The full
  `pre-commit-gate.sh` (typecheck, lint, secret scan, etc.) still runs
  only via Claude Code's PreToolUse hook — terminal commits skip those
  heavier checks by design.

## General

<!-- anchor: general -->
