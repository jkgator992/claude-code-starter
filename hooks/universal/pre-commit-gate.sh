#!/usr/bin/env bash
# Pre-commit gate: blocks `git commit` unless the repo is in a commitable state.
#
# Invocation:
#   - As a Claude Code PreToolUse hook on the Bash tool, matcher "git commit".
#     Payload is JSON on stdin with .tool_input.command. Only runs the gate
#     when the command is `git commit`.
#   - Manually (no stdin) — runs all checks unconditionally.
#
# Blocks (exit 2) if:
#   1. .claude/.types-stale exists                 → run your type regen command
#   2. typecheck fails
#   3. docs/violations.md has unresolved ❌ entries → resolve them first
#
# TODO: replace the typecheck command at the bottom if you don't use npm.
set -euo pipefail

if [[ ! -t 0 ]]; then
  payload=$(cat)
else
  payload=""
fi

if [[ -n "$payload" ]]; then
  tool=$(echo "$payload" | jq -r '.tool_name // ""')
  cmd=$(echo "$payload" | jq -r '.tool_input.command // ""')
  if [[ "$tool" == "Bash" ]]; then
    if [[ ! "$cmd" =~ (^|[[:space:]\;&|])git[[:space:]]+commit([[:space:]]|$) ]]; then
      exit 0
    fi
  fi
fi

problems=()

# ─── Check 1: stale types marker (Supabase projects) ───────────────────────
if [[ -f ".claude/.types-stale" ]]; then
  # TODO: update this message to match your type-regen command.
  problems+=("generated types are stale — run: npm run db:types (or your project's equivalent)")
  while IFS= read -r line; do
    problems+=("    $line")
  done < .claude/.types-stale
fi

# ─── Check 2: typecheck ─────────────────────────────────────────────────────
# TODO: replace `npm run typecheck` with your project's command.
#   - pnpm: pnpm typecheck
#   - yarn: yarn typecheck
#   - python (mypy): mypy .
typecheck_log="/tmp/starter-typecheck-$$.log"
TYPECHECK_CMD="${TYPECHECK_CMD:-npm run typecheck}"
if ! eval "$TYPECHECK_CMD" > "$typecheck_log" 2>&1; then
  problems+=("$TYPECHECK_CMD failed — see ${typecheck_log}")
  while IFS= read -r err; do
    problems+=("    $err")
  done < <(grep -E 'error (TS[0-9]+|\[|:)' "$typecheck_log" 2>/dev/null | head -5 || true)
else
  rm -f "$typecheck_log"
fi

# ─── Check 3: unresolved violations ─────────────────────────────────────────
if [[ -f "docs/violations.md" ]]; then
  # grep -c prints "0" and exits 1 on zero matches; `|| echo 0` would then
  # duplicate the "0" and break `(( ... ))`. `|| true` just suppresses the
  # failure; grep's own "0" output is what we want.
  unresolved=$(grep -c '^❌' docs/violations.md 2>/dev/null || true)
  unresolved=${unresolved:-0}
  if (( unresolved > 0 )); then
    problems+=("docs/violations.md has ${unresolved} unresolved ❌ entries — mark ✅ or remove before committing")
    while IFS= read -r line; do
      problems+=("    $line")
    done < <(grep '^❌' docs/violations.md | head -5)
  fi
fi

if (( ${#problems[@]} > 0 )); then
  echo "pre-commit-gate: commit blocked" >&2
  for p in "${problems[@]}"; do echo "  - $p" >&2; done
  exit 2
fi

echo "pre-commit-gate: ✓ typecheck clean, no unresolved violations" >&2
exit 0
