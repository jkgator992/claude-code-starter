#!/usr/bin/env bash
# PostToolUse advisory: every BullMQ Worker must register BOTH
#   worker.on('error', ...)    AND    worker.on('failed', ...)
# Without these, job failures are silent.
#
# Blocks (exit 2) when a Worker is instantiated without both handlers —
# this is a production-critical pattern.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

case "$file" in
  *.ts|*.tsx|*.js|*.mjs|*.cjs) : ;;
  *) exit 0 ;;
esac
[[ ! -f "$file" ]] && exit 0

if ! grep -Eq '\bnew\s+Worker\s*\(' "$file"; then
  exit 0
fi
if ! grep -Eq "from\s+['\"]bullmq['\"]" "$file"; then
  exit 0
fi

mapfile -t worker_vars < <(
  grep -Eo '(const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*new\s+Worker\s*\(' "$file" \
    | sed -E 's/^(const|let|var)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*=.*/\2/' \
    | sort -u
)

missing=()

check_handler() {
  local event="$1"
  if (( ${#worker_vars[@]} > 0 )); then
    local found=0
    for v in "${worker_vars[@]}"; do
      if grep -Eq "\b${v}\s*\.\s*on\s*\(\s*['\"]${event}['\"]" "$file"; then
        found=1; break
      fi
    done
    (( found == 0 )) && missing+=("$event")
  else
    grep -Eq "\.on\s*\(\s*['\"]${event}['\"]" "$file" || missing+=("$event")
  fi
}

check_handler "error"
check_handler "failed"

# Softer check: job run tracking.
# TODO: if your project tracks job runs in a specific table, update the name here.
tracks_runs=1
if ! grep -Eq '\bscheduled_job_runs\b|\bjob_runs\b' "$file"; then
  tracks_runs=0
fi

if (( ${#missing[@]} > 0 )); then
  echo "check-bullmq-handlers: $file instantiates a BullMQ Worker but is missing:" >&2
  for h in "${missing[@]}"; do echo "  - worker.on('${h}', handler)" >&2; done
  echo "  Without these, job failures are SILENT in production — this is a hard block." >&2
  if (( tracks_runs == 0 )); then
    echo "  (also: no reference to a job-runs table — workers should log job start/completion)" >&2
  fi
  exit 2
fi

if (( tracks_runs == 0 )); then
  echo "check-bullmq-handlers: $file has error/failed handlers but no job-runs tracking" >&2
  echo "  Reminder, not a blocker." >&2
  exit 1
fi

exit 0
