#!/usr/bin/env bash
# PostToolUse on Write|Edit|MultiEdit for the data-access layer:
# extract exported function signatures and write/refresh an entry in
# docs/api-reference.md under the correct domain section.
#
# TODO: adjust LAYER1_PATH and the DOMAIN_RULES list below to match your
# project.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

# TODO: set this to your data-access directory.
LAYER1_PATH="${LAYER1_PATH:-packages/database/operations/}"

[[ "$file" != *"$LAYER1_PATH"*.ts ]] && exit 0
case "$file" in
  *.test.ts|*.spec.ts) exit 0 ;;
  */index.ts|*/vitest.setup.ts) exit 0 ;;
esac
[[ ! -f "$file" ]] && exit 0
[[ ! -f docs/api-reference.md ]] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$file" <<'PY' 2>/dev/null || true
import os, re, sys

src_file = sys.argv[1]
basename = os.path.splitext(os.path.basename(src_file))[0]

try:
    content = open(src_file).read()
except Exception:
    sys.exit(0)

# TODO: customize these keyword → domain rules to match your codebase.
DOMAIN_RULES = [
    (["auth", "signin", "signup", "session"], "Auth"),
    (["user", "profile", "account"],          "Users"),
    (["billing", "subscription", "invoice"],  "Billing"),
    (["admin", "audit"],                      "Admin"),
]
path_lc = src_file.lower()
domain = "General"
for keywords, name in DOMAIN_RULES:
    if any(k in path_lc for k in keywords):
        domain = name
        break

SIG_PATTERNS = [
    re.compile(r'^export\s+(?:async\s+)?function\s+\w+[^{]*', re.MULTILINE),
    re.compile(r'^export\s+const\s+\w+\s*=\s*(?:async\s*)?\([^)]*\)(?:\s*:[^={]+)?\s*=>', re.MULTILINE),
]

sigs = []
for pat in SIG_PATTERNS:
    for m in pat.finditer(content):
        s = m.group(0).rstrip().rstrip("{").rstrip()
        if s and s not in sigs:
            sigs.append(s)

sigs = sigs[:5]
if not sigs:
    sys.exit(0)

entry = "\n".join([
    f"### `{basename}`",
    "```typescript",
    *sigs,
    "```",
    f"_Source: {src_file}_",
    "",
])

path = "docs/api-reference.md"
text = open(path).read()

if f"### `{basename}`" in text:
    sys.exit(0)

domain_header = f"## {domain}"
if domain_header not in text:
    new_text = text.rstrip() + f"\n\n{domain_header}\n{entry}"
    open(path, "w").write(new_text + ("\n" if not new_text.endswith("\n") else ""))
    sys.exit(0)

start = text.index(domain_header)
end = text.find("\n## ", start + len(domain_header))
if end == -1:
    end = len(text)

domain_block = text[start:end]
placeholder_full  = "_No operations yet — will be populated as Layer 1 is built._"
placeholder_short = "_No operations yet._"

if placeholder_full in domain_block:
    new_block = domain_block.replace(placeholder_full, entry.rstrip())
elif placeholder_short in domain_block:
    new_block = domain_block.replace(placeholder_short, entry.rstrip())
else:
    new_block = domain_block.rstrip() + "\n\n" + entry

new_text = text[:start] + new_block
if not new_text.endswith("\n"):
    new_text += "\n"
new_text += text[end:]
open(path, "w").write(new_text)
PY

exit 0
