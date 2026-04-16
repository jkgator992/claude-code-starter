#!/usr/bin/env bash
# PostToolUse on Write|Edit to the data-access layer:
# find (or append) the matching row in docs/traceability.md and fill in
# the Operation File / Test File / Status columns.
#
# TODO: set LAYER1_PATH to match your data-access directory.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

# TODO: adjust to your directory layout.
LAYER1_PATH="${LAYER1_PATH:-packages/database/operations/}"

[[ "$file" != *"$LAYER1_PATH"*.ts ]] && exit 0
case "$file" in
  *.test.ts|*.spec.ts) exit 0 ;;
  */index.ts|*/vitest.setup.ts) exit 0 ;;
esac

[[ ! -f docs/traceability.md ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

basename=$(basename "$file" .ts)
dir=$(dirname "$file")
test_file="${dir}/__tests__/${basename}.test.ts"

python3 - "$basename" "$file" "$test_file" <<'PY' 2>/dev/null || true
import os, sys

basename, src_file, test_file = sys.argv[1], sys.argv[2], sys.argv[3]
path = "docs/traceability.md"
text = open(path).read()

test_col   = test_file if os.path.exists(test_file) else "—"
status_col = "implemented" if os.path.exists(test_file) else "implemented (test pending)"

def parse_row(line):
    if not line.startswith("|"):
        return None
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    return cells if len(cells) >= 5 else None

def render_row(cells):
    return "| " + " | ".join(cells) + " |"

lines = text.splitlines()
updated = False

for i, line in enumerate(lines):
    if src_file in line:
        cells = parse_row(line)
        if cells:
            cells[2] = src_file
            cells[3] = test_col
            cells[4] = status_col
            lines[i] = render_row(cells)
            updated = True
            break

if not updated:
    for i, line in enumerate(lines):
        cells = parse_row(line)
        if not cells:
            continue
        if cells[0].lower() in ("feature", ""):
            continue
        if cells[0].strip("-").lower() == basename.lower():
            cells[2] = src_file
            cells[3] = test_col
            cells[4] = status_col
            lines[i] = render_row(cells)
            updated = True
            break

if not updated:
    new_row = render_row([basename, "—", src_file, test_col, status_col])
    lines.append(new_row)

out = "\n".join(lines)
if text.endswith("\n"):
    out += "\n"
open(path, "w").write(out)
PY

exit 0
