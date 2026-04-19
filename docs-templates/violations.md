# Violations

Open issues that block commits. The `pre-commit-gate.sh` hook refuses
to commit while any `❌` entries remain.

## Format

- Prefix each entry with `❌` for open, `✅` for resolved.
- Include `file:line` and the rule that was violated.
- When resolved, flip `❌` → `✅`. The gate only blocks on `❌`.

## Examples

<!--
Example entries (glyphs intentionally indented so pre-commit-gate.sh's
`^❌` grep does not match example lines):

    ❌ packages/api/routes/user.ts:42 — raw supabase.from() call in route handler (Layer 1 violation)
    ❌ packages/database/operations/users/updateEmail.ts:78 — missing audit_log write
    ✅ apps/web/app/checkout/page.tsx:15 — removed SUPABASE_SERVICE_ROLE_KEY reference from client component
-->
