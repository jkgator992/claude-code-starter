#!/usr/bin/env bash
# install-plugins.sh — install the Octopus multi-LLM plugin for Claude Code.
#
# IMPORTANT: run this from your terminal, NOT from inside Claude Code.
# The `claude plugin` commands restart the plugin host and are not meant
# to run while a Claude Code session is attached.
#
# After this script finishes, open Claude Code in your project and run:
#
#   /octo:setup
#
# The setup wizard will configure providers, authentication, and token-
# optimization presets.
set -euo pipefail

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found on PATH." >&2
  echo "       install Claude Code from https://docs.claude.com/claude-code" >&2
  exit 1
fi

# Detect whether we're running inside an active Claude Code session.
# Claude Code sets CLAUDE_CODE_SESSION_ID (and similar vars). If that's
# present, warn the user.
if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]]; then
  echo "warning: it looks like you're inside a Claude Code session." >&2
  echo "         exit Claude Code and re-run this script from a plain terminal." >&2
  printf "         continue anyway? [y/N] " >&2
  read -r reply </dev/tty || reply="n"
  case "${reply,,}" in y|yes) ;; *) echo "aborted."; exit 1 ;; esac
fi

echo "→ adding Octopus marketplace"
claude plugin marketplace add https://github.com/nyldn/claude-octopus.git

echo "→ installing octo@nyldn-plugins"
claude plugin install octo@nyldn-plugins

cat <<'EOF'

✓ Octopus plugin installed (user level).

Next steps:

1. Open Claude Code in your project directory:

     cd /path/to/your/project
     claude

2. Inside Claude Code, run the Octopus setup wizard:

     /octo:setup

   It will detect your available providers (Claude is already there;
   Codex, Gemini, and Copilot are optional) and configure auth.

3. Claude-only mode works immediately. To enable parallel multi-LLM
   execution, opt-in to Codex / Gemini / Copilot during setup.

4. Quick sanity check inside Claude Code:

     /octo:auto "what does my package.json do?"

   If that returns a smart routed response, you're good.

Full Octopus docs: https://github.com/nyldn/claude-octopus
EOF
