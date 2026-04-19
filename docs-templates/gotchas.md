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

## General

<!-- anchor: general -->
