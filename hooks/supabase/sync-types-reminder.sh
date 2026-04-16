#!/usr/bin/env bash
# PostToolUse reminder: after any migration edit, Supabase types must be
# regenerated or the generated database.ts file drifts out of sync.
#
# TODO: update GENERATED_TYPES_PATH and DB_TYPES_CMD to match your project.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

case "$file" in
  */supabase/migrations/*.sql) : ;;
  *) exit 0 ;;
esac
[[ ! -f "$file" ]] && exit 0

marker=".claude/.types-stale"
mkdir -p "$(dirname "$marker")"
{
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $file"
} >> "$marker"

# TODO: customize these to match your project.
GENERATED_TYPES_PATH="${GENERATED_TYPES_PATH:-packages/shared/types/src/database.ts}"
DB_TYPES_CMD="${DB_TYPES_CMD:-npx supabase gen types typescript --linked 2>/dev/null > $GENERATED_TYPES_PATH}"

echo "sync-types-reminder: migration edited — Supabase types are now stale" >&2
echo "  run: $DB_TYPES_CMD" >&2
echo "  (local dev DB alternative: npx supabase gen types typescript --local > $GENERATED_TYPES_PATH)" >&2
echo "  marker: $marker (cleared automatically after you regenerate types)" >&2

exit 1
