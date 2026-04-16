#!/usr/bin/env bash
# PreToolUse guard (Next.js variant): enforce trust-boundary rules for
# server-only secrets in Next.js App Router projects.
#
# Server secrets are allowed in:
#   - app/api/** (route handlers)
#   - *.server.ts / *.server.tsx (explicit server modules)
#   - files that look like Next.js server actions ('use server')
#
# Server secrets are BLOCKED in:
#   - files with "use client"
#   - any *.tsx / *.jsx that does not sit under app/api or end in .server.tsx
#
# TODO: update the secret-name list and the server path allow-list.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
content=$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // ""')

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) : ;;
  *) exit 0 ;;
esac
case "$file" in
  */.env.example|*.example) exit 0 ;;
esac

# TODO: adjust this list for your project's server-only env vars.
server_only_env='(SUPABASE_SERVICE_ROLE_KEY|STRIPE_SECRET_KEY|STRIPE_WEBHOOK_SECRET|ANTHROPIC_API_KEY|OPENAI_API_KEY|RESEND_API_KEY|SENDGRID_API_KEY|DATABASE_URL|DIRECT_URL)'

if ! echo "$content" | grep -Eq "\b${server_only_env}\b"; then
  exit 0
fi

# Inspect first 20 lines for directives.
first_lines=$(echo "$content" | head -20)
has_use_server=0
has_use_client=0
if echo "$first_lines" | grep -Eq "^['\"]use server['\"]"; then
  has_use_server=1
fi
if echo "$first_lines" | grep -Eq "^['\"]use client['\"]"; then
  has_use_client=1
fi

# Hard reject client components.
if (( has_use_client == 1 )); then
  matched=$(echo "$content" | grep -Eo "\b${server_only_env}\b" | sort -u | head -5 | tr '\n' ' ')
  echo "check-secret-placement (nextjs): client component references server-only secret" >&2
  echo "  file: $file" >&2
  echo "  vars: ${matched}" >&2
  echo "  fix: move this logic into a server action ('use server') or a route handler in app/api/" >&2
  exit 2
fi

# Allow server actions, route handlers, and .server.{ts,tsx} files.
is_allowed=0
case "$file" in
  */app/api/*)            is_allowed=1 ;;
  *.server.ts|*.server.tsx) is_allowed=1 ;;
  */middleware.ts|*/middleware.js) is_allowed=1 ;;
esac
if (( has_use_server == 1 )); then
  is_allowed=1
fi

if (( is_allowed == 1 )); then
  exit 0
fi

matched=$(echo "$content" | grep -Eo "\b${server_only_env}\b" | sort -u | head -5 | tr '\n' ' ')
echo "check-secret-placement (nextjs): server-only secret in a file that may ship to the client" >&2
echo "  file: $file" >&2
echo "  vars: ${matched}" >&2
echo "  fix: one of:" >&2
echo "    - add \"'use server'\" to the top of the file (server action)" >&2
echo "    - rename the file to *.server.ts / *.server.tsx" >&2
echo "    - move the logic into app/api/" >&2
echo "    - use NEXT_PUBLIC_* if the value is actually client-safe (unlikely for these)" >&2
exit 2
