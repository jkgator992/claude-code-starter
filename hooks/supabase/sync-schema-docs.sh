#!/usr/bin/env bash
# PostToolUse on Write to supabase/migrations/*.sql:
# remind which spec doc the migration should also update.
#
# TODO: customize the keyword → spec-file mapping below for your project.
# If you don't keep per-domain spec docs, this hook can be omitted.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

[[ "$file" != *"supabase/migrations/"* ]] && exit 0
[[ "$file" != *.sql ]] && exit 0

basename=$(basename "$file")

# TODO: replace these mappings with the spec-doc structure you actually use.
spec_file=""
if echo "$basename" | grep -Eiq 'auth|user|session'; then
  spec_file="docs/specs/schema/auth.md"
elif echo "$basename" | grep -Eiq 'billing|subscription|payment|stripe'; then
  spec_file="docs/specs/schema/billing.md"
elif echo "$basename" | grep -Eiq 'audit|log|event'; then
  spec_file="docs/specs/schema/audit.md"
fi

[[ -z "$spec_file" ]] && exit 0

jq -n --arg ctx "📋 Migration written: ${basename}
If this migration changes the schema, update the spec:
  ${spec_file}
Also run: npm run db:types  (regenerate TypeScript types)" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'

exit 0
