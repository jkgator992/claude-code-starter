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
echo "Starting wizard (7 questions)…" >&2
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
  case "${decision,,}" in
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
  case "${d,,}" in
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
