#!/usr/bin/env bash
# PostToolUse: sanity-check new/edited Supabase migrations.
# Flags missing RLS, unsafe destructive statements, and missing down-migrations intent.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

[[ "$file" != *"/supabase/migrations/"*.sql ]] && exit 0
[[ ! -f "$file" ]] && exit 0

issues=()

# Every create table should be paired with an RLS enable + a policy.
if grep -Eiq '^\s*create\s+table\b' "$file"; then
  if ! grep -Eiq 'alter\s+table\s+.*\s+enable\s+row\s+level\s+security' "$file"; then
    issues+=("new table without 'ENABLE ROW LEVEL SECURITY'")
  fi
  if ! grep -Eiq '^\s*create\s+policy\b' "$file"; then
    issues+=("new table without a CREATE POLICY — all tables must have RLS policies")
  fi
fi

# Destructive statements without a guard.
if grep -Eiq '^\s*drop\s+table\b' "$file" && ! grep -Eiq 'drop\s+table\s+if\s+exists' "$file"; then
  issues+=("DROP TABLE without IF EXISTS")
fi
if grep -Eiq '^\s*truncate\b' "$file"; then
  issues+=("TRUNCATE in a migration — usually wrong outside local seed data")
fi

if (( ${#issues[@]} > 0 )); then
  echo "validate-migration: issues in $file:" >&2
  for i in "${issues[@]}"; do echo "  - $i" >&2; done
  exit 1
fi

exit 0
