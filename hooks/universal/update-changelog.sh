#!/usr/bin/env bash
# PostToolUse Bash hook: when a `git commit` just ran, append the new commit
# to CHANGELOG.md under today's section.
set -euo pipefail

payload=$(cat)
tool=$(echo "$payload" | jq -r '.tool_name // ""')
cmd=$(echo "$payload" | jq -r '.tool_input.command // ""')

[[ "$tool" != "Bash" ]] && exit 0

if [[ ! "$cmd" =~ (^|[[:space:]\;\&\|])git[[:space:]]+commit([[:space:]]|$) ]]; then
  exit 0
fi
if [[ "$cmd" == *"--amend"* ]]; then
  exit 0
fi

[[ ! -f CHANGELOG.md ]] && exit 0

sha=$(git log -1 --format=%h 2>/dev/null || echo "")
msg=$(git log -1 --format=%s 2>/dev/null || echo "")
[[ -z "$msg" || -z "$sha" ]] && exit 0

state_file=".claude/.changelog-lastsha"
mkdir -p .claude
last_sha=$([[ -f "$state_file" ]] && cat "$state_file" || echo "")
if [[ "$last_sha" == "$sha" ]]; then
  exit 0
fi

cc_re='^(feat|fix|chore|schema|ops|security|test|docs)(\([^)]*\))?:[[:space:]]*(.*)$'
if [[ "$msg" =~ $cc_re ]]; then
  type="${BASH_REMATCH[1]}"
  subject="${BASH_REMATCH[3]}"
else
  type="chore"
  subject="$msg"
fi

date=$(date '+%Y-%m-%d')
line="- ${type}: ${subject} (${sha})"

python3 - "$date" "$line" <<'PY' 2>/dev/null || true
import os, re, sys
date, line = sys.argv[1], sys.argv[2]
path = "CHANGELOG.md"
text = open(path).read()

if line in text:
    sys.exit(0)

today_header = f"## {date}"

if today_header in text:
    idx = text.index(today_header)
    eol = text.find("\n", idx)
    new_text = text[:eol + 1] + line + "\n" + text[eol + 1:]
else:
    m = re.search(r"^## Unreleased\s*$", text, re.MULTILINE)
    if not m:
        new_text = text.rstrip() + f"\n\n{today_header}\n{line}\n"
    else:
        insert_at = m.end()
        new_text = (
            text[:insert_at]
            + f"\n\n{today_header}\n{line}"
            + text[insert_at:]
        )

with open(path, "w") as f:
    f.write(new_text)
PY

echo "$sha" > "$state_file"

exit 0
