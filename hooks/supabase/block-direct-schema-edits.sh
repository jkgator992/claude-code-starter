#!/usr/bin/env bash
# PreToolUse guard: require schema changes to go through supabase/migrations/.
# Blocks edits to generated types and any attempt to write SQL outside migrations/.
#
# TODO: update the generated-types path below to match where your project
# stores the Supabase-generated database.ts file.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
content=$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // ""')

# TODO: set your generated types path here.
# Common paths:
#   packages/shared/types/src/database.ts
#   src/types/database.ts
#   lib/database.types.ts
GENERATED_TYPES_PATH="${GENERATED_TYPES_PATH:-packages/shared/types/src/database.ts}"

if [[ "$file" == *"$GENERATED_TYPES_PATH" ]]; then
  echo "block-direct-schema-edits: $file is generated — run 'supabase gen types typescript' instead" >&2
  exit 2
fi

# Any .sql file outside supabase/migrations/ (and outside seed.sql) is suspicious.
if [[ "$file" == *.sql ]]; then
  case "$file" in
    */supabase/migrations/*.sql|*/supabase/seed.sql) : ;;
    *)
      echo "block-direct-schema-edits: SQL files must live in supabase/migrations/ (got $file)" >&2
      echo "  Use: npx supabase migration new <name>" >&2
      exit 2
      ;;
  esac
fi

# DDL-looking content in SQL files outside migrations/seed.
if [[ "$file" == *.sql && "$file" != *"/supabase/migrations/"* && "$file" != *"/supabase/seed.sql" ]]; then
  if echo "$content" | grep -Eiq '^\s*(create|alter|drop)\s+(table|schema|policy|index|type|function)\b'; then
    echo "block-direct-schema-edits: DDL detected outside supabase/migrations/ in $file" >&2
    exit 2
  fi
fi

exit 0
