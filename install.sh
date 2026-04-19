#!/usr/bin/env bash
# install.sh — one-command installer for claude-code-starter.
#
# Behavior:
#   1. Resolve the starter directory (the dir this script lives in).
#   2. Run wizard.sh and capture JSON answers.
#   3. For each file from templates/ + matching hooks/ + matching agents/
#      + skills/ + docs-templates/ + settings-templates/:
#        - if target doesn't exist → copy.
#        - if target exists → show diff, prompt overwrite/merge/skip.
#   4. Stamp TODO: markers in CLAUDE.md / AGENTS.md with wizard answers
#      where they map cleanly.
#   5. Log every decision to .claude-starter.log in the target project.
#   6. Print a summary and Octopus next-steps.
#
# Requirements: bash 4+, jq, git, diff.
set -euo pipefail

STARTER=$(cd "$(dirname "$0")" && pwd)
TARGET=${INSTALL_TARGET:-$PWD}
LOG="$TARGET/.claude-starter.log"
STATE="$TARGET/.claude-starter.state"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
for cmd in jq diff git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' not found on PATH" >&2
    exit 1
  fi
done

if [[ "$STARTER" == "$TARGET" ]]; then
  echo "error: refusing to install the starter kit over itself." >&2
  echo "       cd into your project directory and re-run:" >&2
  echo "       bash $STARTER/install.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG")"
: > "$LOG"
echo "# claude-code-starter install log  ($(date -u +%FT%TZ))" >> "$LOG"
echo "# starter: $STARTER" >> "$LOG"
echo "# target:  $TARGET"  >> "$LOG"

# ─── Wizard ──────────────────────────────────────────────────────────────────
echo "Starting wizard (10 questions)…" >&2
wizard_out=$(bash "$STARTER/wizard.sh")
answers=$(echo "$wizard_out" | tail -n +1 | tr -d '\n' | grep -o '{.*}$' || echo '{}')
if [[ -z "$answers" || "$answers" == '{}' ]]; then
  # Fallback: last non-empty line should be JSON.
  answers=$(echo "$wizard_out" | awk 'NF' | tail -1)
fi
if ! echo "$answers" | jq . >/dev/null 2>&1; then
  echo "error: wizard did not emit valid JSON on stdout" >&2
  echo "--- wizard output ---" >&2
  echo "$wizard_out" >&2
  exit 1
fi
echo "$answers" > "$STATE"
echo "# wizard answers:" >> "$LOG"
echo "$answers" | jq . >> "$LOG"

PROJECT_NAME=$(echo "$answers" | jq -r .project_name)
PROJECT_DESC=$(echo "$answers" | jq -r .project_desc)
TECH_STACK=$(echo "$answers"   | jq -r .tech_stack)
USE_SUPABASE=$(echo "$answers" | jq -r .use_supabase)
TEST_RUNNER=$(echo "$answers"  | jq -r .test_runner)
PKG_MGR=$(echo "$answers"      | jq -r .pkg_mgr)
ENABLE_PARALLEL_DEV=$(echo "$answers" | jq -r .enable_parallel_dev)
ENABLE_AUDITOR=$(echo "$answers"      | jq -r .enable_auditor)
EXISTING_PROJECT=$(echo "$answers"    | jq -r .existing_project)

# ─── File-by-file install ────────────────────────────────────────────────────
# install_file <src> <dst>  — shows diff on conflict, prompts overwrite/merge/skip.
install_file() {
  local src="$1"
  local dst="$2"
  local decision

  mkdir -p "$(dirname "$dst")"

  if [[ ! -e "$dst" ]]; then
    cp "$src" "$dst"
    chmod --reference="$src" "$dst" 2>/dev/null || chmod "$(stat -f%Op "$src" 2>/dev/null || echo 644)" "$dst" 2>/dev/null || true
    # Preserve executable bit on .sh files.
    case "$src" in *.sh) chmod +x "$dst" ;; esac
    echo "installed  $dst" | tee -a "$LOG" >&2
    return
  fi

  # File exists — check if identical.
  if diff -q "$src" "$dst" >/dev/null 2>&1; then
    echo "unchanged  $dst" | tee -a "$LOG" >&2
    return
  fi

  # Different. Show diff.
  echo "" >&2
  echo "── conflict: $dst" >&2
  echo "── diff (incoming < existing >):" >&2
  diff -u "$dst" "$src" | sed 's/^/    /' >&2 || true
  echo "" >&2
  printf "    [o]verwrite  [m]erge  [s]kip  > " >&2
  IFS= read -r decision </dev/tty || decision="s"
  decision_lower=$(printf "%s" "$decision" | tr "[:upper:]" "[:lower:]")
  case "$decision_lower" in
    o|overwrite)
      cp "$src" "$dst"
      case "$src" in *.sh) chmod +x "$dst" ;; esac
      echo "overwrote  $dst" | tee -a "$LOG" >&2
      ;;
    m|merge)
      local ed="${EDITOR:-vi}"
      echo "opening $ed on both files — edit $dst in place, then save/quit" >&2
      "$ed" "$dst" "$src" </dev/tty >/dev/tty 2>&1 || true
      echo "merged     $dst" | tee -a "$LOG" >&2
      ;;
    *)
      echo "skipped    $dst" | tee -a "$LOG" >&2
      ;;
  esac
}

# ─── 1. Settings preset ──────────────────────────────────────────────────────
settings_preset="minimal"
if [[ "$USE_SUPABASE" == "yes" ]]; then
  settings_preset="supabase"
elif [[ "$TECH_STACK" == "nextjs" || "$TECH_STACK" == "node" ]]; then
  settings_preset="full"
fi
echo "# settings preset: $settings_preset" >> "$LOG"
install_file "$STARTER/settings-templates/settings.$settings_preset.json" "$TARGET/.claude/settings.json"

# ─── 2. Universal hooks (always) ─────────────────────────────────────────────
for f in "$STARTER"/hooks/universal/*.sh; do
  [[ -e "$f" ]] || continue
  install_file "$f" "$TARGET/.claude/hooks/$(basename "$f")"
done

# ─── 3. Stack-specific hooks ─────────────────────────────────────────────────
if [[ "$USE_SUPABASE" == "yes" ]]; then
  for f in "$STARTER"/hooks/supabase/*.sh; do
    [[ -e "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/hooks/$(basename "$f")"
  done
fi

if [[ "$TECH_STACK" == "nextjs" ]]; then
  for f in "$STARTER"/hooks/nextjs/*.sh; do
    [[ -e "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/hooks/$(basename "$f")"
  done
fi

# BullMQ hooks: install if Node.js stack and Supabase (they often go together)
# or let user opt in via env var.
if [[ "$TECH_STACK" == "node" || "${INSTALL_BULLMQ:-0}" == "1" ]]; then
  for f in "$STARTER"/hooks/bullmq/*.sh; do
    [[ -e "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/hooks/$(basename "$f")"
  done
fi

# ─── 4. Agents ───────────────────────────────────────────────────────────────
for f in "$STARTER"/agents/universal/*.md; do
  [[ -e "$f" ]] || continue
  install_file "$f" "$TARGET/.claude/agents/$(basename "$f")"
done

if [[ "$USE_SUPABASE" == "yes" ]]; then
  for f in "$STARTER"/agents/supabase/*.md; do
    [[ -e "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/agents/$(basename "$f")"
  done
fi

case "$TECH_STACK" in
  nextjs)
    for f in "$STARTER"/agents/nextjs/*.md; do
      [[ -e "$f" ]] || continue
      install_file "$f" "$TARGET/.claude/agents/$(basename "$f")"
    done
    ;;
  react-native)
    for f in "$STARTER"/agents/react-native/*.md; do
      [[ -e "$f" ]] || continue
      install_file "$f" "$TARGET/.claude/agents/$(basename "$f")"
    done
    ;;
  node)
    for f in "$STARTER"/agents/node/*.md; do
      [[ -e "$f" ]] || continue
      install_file "$f" "$TARGET/.claude/agents/$(basename "$f")"
    done
    ;;
esac

# ─── 5. Skills (always install all) ──────────────────────────────────────────
for d in "$STARTER"/skills/*/; do
  [[ -d "$d" ]] || continue
  skill_name=$(basename "$d")
  for f in "$d"*.md; do
    [[ -e "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/skills/$skill_name/$(basename "$f")"
  done
done

# ─── 6. Docs templates ───────────────────────────────────────────────────────
for f in "$STARTER"/docs-templates/*.md; do
  [[ -e "$f" ]] || continue
  install_file "$f" "$TARGET/docs/$(basename "$f")"
done
if [[ -d "$STARTER/docs-templates/tests" ]]; then
  for f in "$STARTER"/docs-templates/tests/*; do
    [[ -e "$f" ]] || continue
    install_file "$f" "$TARGET/docs/tests/$(basename "$f")"
  done
fi

# ─── 6a. Runbooks + pre-launch-auditor (if auditor enabled) ────────────────
if [[ "$ENABLE_AUDITOR" == "yes" ]]; then
  if [[ -d "$STARTER/docs-templates/runbooks" ]]; then
    for f in "$STARTER"/docs-templates/runbooks/*.md; do
      [[ -e "$f" ]] || continue
      install_file "$f" "$TARGET/docs/runbooks/$(basename "$f")"
    done
  fi

  if [[ -f "$STARTER/agents/universal/pre-launch-auditor.md" ]]; then
    install_file "$STARTER/agents/universal/pre-launch-auditor.md" \
                 "$TARGET/.claude/agents/pre-launch-auditor.md"
  fi

  if [[ -f "$STARTER/templates/tests/load/smoke.k6.js" ]]; then
    install_file "$STARTER/templates/tests/load/smoke.k6.js" \
                 "$TARGET/tests/load/smoke.k6.js"
    install_file "$STARTER/templates/tests/load/README.md" \
                 "$TARGET/tests/load/README.md"
  fi
fi

# ─── 6b. Parallel dev system (if enabled) ──────────────────────────────────
if [[ "$ENABLE_PARALLEL_DEV" == "yes" ]]; then
  if [[ -f "$STARTER/agents/universal/dispatcher.md" ]]; then
    install_file "$STARTER/agents/universal/dispatcher.md" \
                 "$TARGET/.claude/agents/dispatcher.md"
  fi

  if [[ -d "$STARTER/commands/universal" ]]; then
    for f in "$STARTER"/commands/universal/*.md; do
      [[ -e "$f" ]] || continue
      install_file "$f" "$TARGET/.claude/commands/$(basename "$f")"
    done
  fi

  if [[ "$USE_SUPABASE" == "yes" && -f "$STARTER/hooks/supabase/check-migration-lock.sh" ]]; then
    install_file "$STARTER/hooks/supabase/check-migration-lock.sh" \
                 "$TARGET/.claude/hooks/check-migration-lock.sh"
    chmod +x "$TARGET/.claude/hooks/check-migration-lock.sh" 2>/dev/null || true
  fi

  # Install .git/hooks/pre-commit shim so terminal commits also hit the
  # migration-lock gate (Claude Code PreToolUse already covers Claude's
  # own commits via pre-commit-gate.sh).
  if [[ -f "$STARTER/templates/git-hooks/pre-commit.sh" && -d "$TARGET/.git" ]]; then
    git_pre_commit="$TARGET/.git/hooks/pre-commit"
    git_pre_commit_src="$STARTER/templates/git-hooks/pre-commit.sh"
    mkdir -p "$(dirname "$git_pre_commit")"
    if [[ -e "$git_pre_commit" ]]; then
      echo "" >&2
      echo "⚠️  $git_pre_commit already exists." >&2
      printf "    [s]kip  [o]verwrite  [b]ackup-and-install  > " >&2
      IFS= read -r choice </dev/tty || choice="s"
      choice_lower=$(printf "%s" "$choice" | tr "[:upper:]" "[:lower:]")
      case "$choice_lower" in
        o|overwrite)
          cp "$git_pre_commit_src" "$git_pre_commit"
          chmod +x "$git_pre_commit"
          echo "overwrote  $git_pre_commit" | tee -a "$LOG" >&2
          ;;
        b|backup)
          ts=$(date +%s)
          mv "$git_pre_commit" "${git_pre_commit}.bak.${ts}"
          cp "$git_pre_commit_src" "$git_pre_commit"
          chmod +x "$git_pre_commit"
          echo "backed up  ${git_pre_commit}.bak.${ts}" | tee -a "$LOG" >&2
          echo "installed  $git_pre_commit" | tee -a "$LOG" >&2
          ;;
        *)
          echo "skipped    $git_pre_commit (terminal commits will NOT be gated by migration-lock)" | tee -a "$LOG" >&2
          echo "           install manually later: cp $git_pre_commit_src $git_pre_commit && chmod +x $git_pre_commit" >&2
          ;;
      esac
    else
      cp "$git_pre_commit_src" "$git_pre_commit"
      chmod +x "$git_pre_commit"
      echo "installed  $git_pre_commit (migration-lock gate for terminal commits)" | tee -a "$LOG" >&2
    fi
  elif [[ -f "$STARTER/templates/git-hooks/pre-commit.sh" && ! -d "$TARGET/.git" ]]; then
    echo "note: $TARGET is not a git repo root; skipped .git/hooks/pre-commit install." | tee -a "$LOG" >&2
  fi

  if [[ -f "$STARTER/templates/coordination-README.md" ]]; then
    install_file "$STARTER/templates/coordination-README.md" \
                 "$TARGET/.claude/coordination/README.md"
  fi

  if [[ -f "$STARTER/templates/jira-ticket-template.md" ]]; then
    install_file "$STARTER/templates/jira-ticket-template.md" \
                 "$TARGET/.claude/templates/jira-ticket-template.md"
  fi
fi

# ─── 7. CLAUDE.md / AGENTS.md with substitutions ─────────────────────────────
stamp_template() {
  # stamp_template <src> <dst>  — substitutes known vars, leaves TODO: markers.
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  local tmp
  tmp=$(mktemp)

  # Pre-compute values with TODO: fallbacks.
  local pname="${PROJECT_NAME:-TODO: project name}"
  local pdesc="${PROJECT_DESC:-TODO: one-sentence description of your project}"
  local stack="${TECH_STACK:-TODO: tech stack}"
  local sup="${USE_SUPABASE:-no}"
  local runner="${TEST_RUNNER:-TODO: test runner}"
  local pm="${PKG_MGR:-TODO: package manager}"

  sed \
    -e "s|{{PROJECT_NAME}}|$pname|g" \
    -e "s|{{PROJECT_DESC}}|$pdesc|g" \
    -e "s|{{TECH_STACK}}|$stack|g" \
    -e "s|{{USE_SUPABASE}}|$sup|g" \
    -e "s|{{TEST_RUNNER}}|$runner|g" \
    -e "s|{{PKG_MGR}}|$pm|g" \
    "$src" > "$tmp"

  if [[ ! -e "$dst" ]]; then
    mv "$tmp" "$dst"
    echo "installed  $dst" | tee -a "$LOG" >&2
    return
  fi

  if diff -q "$tmp" "$dst" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "unchanged  $dst" | tee -a "$LOG" >&2
    return
  fi

  echo "" >&2
  echo "── conflict: $dst" >&2
  echo "── diff (incoming < existing >):" >&2
  diff -u "$dst" "$tmp" | sed 's/^/    /' >&2 || true
  echo "" >&2
  printf "    [o]verwrite  [m]erge  [s]kip  > " >&2
  local d; IFS= read -r d </dev/tty || d="s"
  d_lower=$(printf "%s" "$d" | tr "[:upper:]" "[:lower:]")
  case "$d_lower" in
    o|overwrite) mv "$tmp" "$dst"; echo "overwrote  $dst" | tee -a "$LOG" >&2 ;;
    m|merge)
      local ed="${EDITOR:-vi}"
      echo "opening $ed on both files — edit $dst in place, then save/quit" >&2
      "$ed" "$dst" "$tmp" </dev/tty >/dev/tty 2>&1 || true
      rm -f "$tmp"
      echo "merged     $dst" | tee -a "$LOG" >&2
      ;;
    *)           rm -f "$tmp"; echo "skipped    $dst" | tee -a "$LOG" >&2 ;;
  esac
}

stamp_template "$STARTER/templates/CLAUDE.md"  "$TARGET/CLAUDE.md"
stamp_template "$STARTER/templates/AGENTS.md"  "$TARGET/AGENTS.md"

# ─── 7a. Grandfather mode for existing projects with auditor ──────────────
if [[ "$EXISTING_PROJECT" == "yes" && "$ENABLE_AUDITOR" == "yes" ]]; then
  mkdir -p "$TARGET/.claude"
  BASELINE_SHA=$(cd "$TARGET" && git rev-parse HEAD 2>/dev/null || echo "unknown")
  cat > "$TARGET/.claude/pre-launch-config.json" <<GRANDFATHER_EOF
{
  "grandfather_baseline_sha": "$BASELINE_SHA",
  "critical_path_globs": [
    "apps/api/src/webhooks/**",
    "apps/api/src/auth/**",
    "packages/api/src/webhooks/**",
    "packages/api/src/auth/**",
    "supabase/migrations/**"
  ],
  "_note": "Grandfather mode ON. pre-launch-auditor only BLOCKs on findings in files changed after baseline SHA. Delete this file to return to strict mode."
}
GRANDFATHER_EOF
  echo "installed  $TARGET/.claude/pre-launch-config.json (grandfather mode enabled)" | tee -a "$LOG" >&2
fi

# ─── 8. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "=== install complete ==="
echo ""
echo "Log:        $LOG"
echo "Answers:    $STATE"
echo ""
echo "Unresolved TODOs in installed files:"
if command -v grep >/dev/null 2>&1; then
  grep -rn "TODO:" "$TARGET/.claude" "$TARGET/CLAUDE.md" "$TARGET/AGENTS.md" 2>/dev/null | head -20 || true
fi
echo ""
echo "Next steps:"
echo "  1. Review .claude/settings.json and adjust the hook list if needed."
echo "  2. Fill in TODO: markers in CLAUDE.md and AGENTS.md."
echo "  3. (Optional) Install Octopus multi-LLM plugin:"
echo "     bash $STARTER/plugins/install-plugins.sh"
echo "     then open Claude Code and run: /octo:setup"
echo ""

if [[ "$ENABLE_PARALLEL_DEV" == "yes" ]]; then
  echo "Parallel dev system enabled. One-time setup:"
  echo "  a) Create coordination directory (outside repo, visible from worktrees):"
  echo "     COORD=\"\$(git rev-parse --git-common-dir)/../project-coordination\""
  echo "     mkdir -p \"\$COORD\" && touch \"\$COORD/active-worktrees.md\""
  echo "  b) Add to .gitignore: project-coordination/"
  echo "  c) Fill in placeholders in .claude/commands/*.md"
  echo "     (Jira cloud ID, Atlassian site URL)"
  echo "  d) Wire check-migration-lock.sh into pre-commit-gate.sh"
  echo "     (see docs/runbooks/parallel-development.md)"
  echo ""
fi

if [[ "$ENABLE_AUDITOR" == "yes" ]]; then
  echo "Pre-launch auditor enabled. First-week tasks:"
  echo "  a) Fill in docs/runbooks/*.md placeholders (vendor contacts first)"
  echo "  b) Run one drill per runbook to populate 'Last drill' timestamps"
  echo "  c) Fill in tests/load/smoke.k6.js placeholders (staging URL, endpoints)"
  echo "  d) Verify: run pre-launch-auditor tier 1 on HEAD (inside Claude Code)"
  echo ""
fi

if [[ "$EXISTING_PROJECT" == "yes" ]]; then
  echo "Existing-project install. Important reminders:"
  echo ""
  if [[ "$ENABLE_AUDITOR" == "yes" ]]; then
    echo "  - Grandfather mode enabled for pre-launch-auditor"
    echo "    Only new code (after current HEAD) will BLOCK; legacy findings tracked separately"
  fi
  if [[ "$ENABLE_PARALLEL_DEV" == "yes" ]]; then
    echo "  - Migration-lock hook will block commits without a ticket worktree"
    echo "    Announce to your team BEFORE merging this install"
  fi
  echo "  - Review every 'overwrote' entry in $LOG — those replaced existing content"
  echo "  - Recommended first PR: install only; adopt new flow in follow-up PRs"
  echo ""
fi


