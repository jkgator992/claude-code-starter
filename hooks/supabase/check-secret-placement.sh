#!/usr/bin/env bash
# PreToolUse guard: enforce trust-boundary rules for server-only secrets.
#
# Server-only secrets must NEVER appear in:
#   - client bundles (apps/mobile/**, any file with "use client")
#   - shared UI packages that get imported by clients
#
# Allowed homes:
#   - server-only directories (apps/api/**, apps/admin/**)
#   - explicit server modules (*.server.ts, app/api/*)
#   - .env.example (documentation)
#
# TODO: update the server-only secret names below to match YOUR project's
# environment variables, and update the allowed-path list to match YOUR
# directory layout.
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

# TODO: adjust this list for your project.
# Three forms (ENV, camelCase, snake_case) so assignment chains are caught.
server_only_env='(SUPABASE_SERVICE_ROLE_KEY|STRIPE_SECRET_KEY|STRIPE_WEBHOOK_SECRET|STRIPE_RESTRICTED_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY|RESEND_API_KEY|SENDGRID_API_KEY|R2_SECRET_ACCESS_KEY|R2_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|ONESIGNAL_REST_API_KEY|UPSTASH_REDIS_REST_TOKEN)'
server_only_camel='(serviceRoleKey|stripeSecretKey|stripeWebhookSecret|stripeRestrictedKey|anthropicApiKey|openAiApiKey|resendApiKey|sendgridApiKey|r2SecretAccessKey|r2AccessKeyId|awsSecretAccessKey|oneSignalRestApiKey|upstashRedisRestToken)'
server_only_snake='(service_role_key|stripe_secret_key|stripe_webhook_secret|stripe_restricted_key|anthropic_api_key|openai_api_key|resend_api_key|sendgrid_api_key|r2_secret_access_key|r2_access_key_id|aws_secret_access_key|onesignal_rest_api_key|upstash_redis_rest_token)'

server_only="${server_only_env}|${server_only_camel}|${server_only_snake}"

if ! echo "$content" | grep -Eq "\b(${server_only})\b"; then
  exit 0
fi

# TODO: adjust this list of allowed paths for your directory layout.
is_allowed_path=0
case "$file" in
  */apps/api/*)                 is_allowed_path=1 ;;
  */apps/admin/*)               is_allowed_path=1 ;;
  */apps/web/*.server.ts|\
  */apps/web/**/*.server.ts|\
  */apps/web/app/api/*)         is_allowed_path=1 ;;
  */supabase/functions/*)       is_allowed_path=1 ;;
  */scripts/*)                  is_allowed_path=1 ;;
  */server/*)                   is_allowed_path=1 ;;
esac

# "use client" files are client components, regardless of path.
first_lines=$(echo "$content" | head -20)
if echo "$first_lines" | grep -Eq "^['\"]use client['\"]"; then
  is_allowed_path=0
  client_directive=1
else
  client_directive=0
fi

if [[ $is_allowed_path -eq 1 ]]; then
  exit 0
fi

matched=$(echo "$content" | grep -Eo "\b(${server_only})\b" | sort -u | head -5 | tr '\n' ' ')
echo "check-secret-placement: server-only secret referenced in client-reachable code" >&2
echo "  file: $file" >&2
echo "  vars: ${matched}" >&2
if [[ $client_directive -eq 1 ]]; then
  echo "  reason: file has 'use client' directive — cannot reference server-only env vars" >&2
else
  echo "  reason: server secrets are allowed only in server-side paths (see hook source for the allow-list)" >&2
fi
echo "  use NEXT_PUBLIC_* / EXPO_PUBLIC_* for values that need to reach the client" >&2
exit 2
