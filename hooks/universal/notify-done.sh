#!/usr/bin/env bash
# Stop hook: macOS notification when Claude finishes a turn.
# No-op on non-macOS platforms.
set -euo pipefail

# TODO: customize the title / body to name your project.
title="Claude Code"
msg="Turn complete in $(basename "$PWD")"

if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$msg\" with title \"$title\"" >/dev/null 2>&1 || true
fi

# TODO (linux): uncomment to use notify-send on Linux desktop.
# if command -v notify-send >/dev/null 2>&1; then
#   notify-send "$title" "$msg" >/dev/null 2>&1 || true
# fi

exit 0
