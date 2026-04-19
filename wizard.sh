#!/usr/bin/env bash
# wizard.sh — ask 10 setup questions and emit the answers as JSON.
# Called by install.sh. Safe to run standalone (prints JSON on the last line).
set -euo pipefail

ask() {
  # ask "prompt" "default" "var_name"
  local prompt="$1"
  local default="$2"
  local __var="$3"
  local reply

  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r reply </dev/tty || reply=""
  [[ -z "$reply" ]] && reply="$default"
  printf -v "$__var" '%s' "$reply"
}

ask_choice() {
  # ask_choice "prompt" "opt1|opt2|opt3" "default" "var_name"
  local prompt="$1"
  local opts="$2"
  local default="$3"
  local __var="$4"
  local reply

  printf '%s (%s) [%s]: ' "$prompt" "$opts" "$default" >&2
  IFS= read -r reply </dev/tty || reply=""
  [[ -z "$reply" ]] && reply="$default"
  printf -v "$__var" '%s' "$reply"
}

printf '\n=== claude-code-starter wizard ===\n' >&2
printf 'Answer 10 questions. Blank answers become TODO: markers.\n\n' >&2

# 1. Project name (default: cwd basename)
default_name=$(basename "$PWD")
ask "1. Project name" "$default_name" PROJECT_NAME

# 2. One-sentence description
ask "2. One-sentence description" "" PROJECT_DESC

# 3. Tech stack
ask_choice "3. Tech stack" "nextjs|react-native|node|python|other" "nextjs" TECH_STACK

# 4. Using Supabase?
ask_choice "4. Using Supabase?" "yes|no" "no" USE_SUPABASE

# 5. Test runner
case "$TECH_STACK" in
  python) default_runner="pytest" ;;
  *)      default_runner="vitest" ;;
esac
ask_choice "5. Test runner" "vitest|jest|pytest|other" "$default_runner" TEST_RUNNER

# 6. Package manager
case "$TECH_STACK" in
  python) default_pm="pip" ;;
  *)      default_pm="npm" ;;
esac
ask_choice "6. Package manager" "npm|yarn|pnpm|pip|other" "$default_pm" PKG_MGR

# 7. Auto-detect directory structure?
ask_choice "7. Auto-detect directory structure?" "yes|no" "yes" AUTO_DETECT

# 8. Parallel dev system?
ask_choice "8. Enable parallel dev system (git worktrees + Jira ticket lifecycle)?" "yes|no" "no" ENABLE_PARALLEL_DEV

# 9. Pre-launch auditor + runbooks?
ask_choice "9. Enable pre-launch auditor + operational runbooks?" "yes|no" "yes" ENABLE_AUDITOR

# 10. Existing project (not fresh scaffold)?
ask_choice "10. Is this an existing project (has its own git history, existing agents/hooks)?" "yes|no" "no" EXISTING_PROJECT

# ─── Directory detection (best-effort, informational) ────────────────────────
DETECTED_LAYOUT="unknown"
DETECTED_APPS="[]"
DETECTED_PACKAGES="[]"
if [[ "$AUTO_DETECT" == "yes" ]]; then
  detect_out=$(ls -1 . 2>/dev/null || echo "")
  if echo "$detect_out" | grep -q '^apps$' && echo "$detect_out" | grep -q '^packages$'; then
    DETECTED_LAYOUT="monorepo"
    if [[ -d apps ]]; then
      DETECTED_APPS=$(ls -1 apps 2>/dev/null | jq -R . | jq -s -c .)
    fi
    if [[ -d packages ]]; then
      DETECTED_PACKAGES=$(ls -1 packages 2>/dev/null | jq -R . | jq -s -c .)
    fi
  elif [[ -f package.json ]]; then
    DETECTED_LAYOUT="single-node"
  elif [[ -f pyproject.toml || -f setup.py ]]; then
    DETECTED_LAYOUT="single-python"
  fi
fi

# ─── Emit JSON on the last line ──────────────────────────────────────────────
# install.sh captures the last line of stdout as JSON.
jq -n \
  --arg project_name   "$PROJECT_NAME" \
  --arg project_desc   "$PROJECT_DESC" \
  --arg tech_stack     "$TECH_STACK" \
  --arg use_supabase   "$USE_SUPABASE" \
  --arg test_runner    "$TEST_RUNNER" \
  --arg pkg_mgr        "$PKG_MGR" \
  --arg enable_parallel_dev "$ENABLE_PARALLEL_DEV" \
  --arg enable_auditor "$ENABLE_AUDITOR" \
  --arg existing_project "$EXISTING_PROJECT" \
  --arg auto_detect    "$AUTO_DETECT" \
  --arg layout         "$DETECTED_LAYOUT" \
  --argjson apps       "$DETECTED_APPS" \
  --argjson packages   "$DETECTED_PACKAGES" \
  '{
    project_name: $project_name,
    project_desc: $project_desc,
    tech_stack: $tech_stack,
    use_supabase: $use_supabase,
    test_runner: $test_runner,
    pkg_mgr: $pkg_mgr,
    enable_parallel_dev: $enable_parallel_dev,
    enable_auditor: $enable_auditor,
    existing_project: $existing_project,
    auto_detect: $auto_detect,
    detected: {
      layout: $layout,
      apps: $apps,
      packages: $packages
    }
  }'
