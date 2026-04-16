#!/usr/bin/env bash
# PostToolUse capturer: scans edited files for tagged comments and routes
# them to shared docs. Never blocks — always exits 0.
#
# Tags recognised (line comments only, // or --):
#   GOTCHA  → docs/gotchas.md (classified by keyword into a section)
#   BUG     → docs/gotchas.md (classified)
#   WARN    → docs/gotchas.md (classified)
#   HACK    → docs/gotchas.md (classified)
#   NOTE    → docs/gotchas.md (classified)
#   TODO    → docs/todos.md  (with file:line prefix for traceability)
#
# Reads the post-edit file from disk (not tool_input) so line numbers are
# accurate and we see the final state of the file.
set -euo pipefail

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // ""')

[[ -z "$file" ]] && exit 0
[[ ! -f "$file" ]] && exit 0

# Only scan source code. Skip the docs we're writing into (infinite loop risk).
case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.sql|*.py|*.go|*.rs|*.rb) : ;;
  *) exit 0 ;;
esac
case "$file" in
  */docs/gotchas.md|*/docs/todos.md) exit 0 ;;
esac

# All heavy lifting in python3. Fail silently on any error — this hook is
# best-effort capture, not a guard.
command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$file" <<'PY' 2>/dev/null || true
import os, re, sys

file_path = sys.argv[1]
try:
    src = open(file_path).read()
except Exception:
    sys.exit(0)

# ─── Tag extraction ─────────────────────────────────────────────────────────
# Match // or -- or # comment markers.
TAG_RE = re.compile(
    r'(?:^\s*|\S\s+)(?://|--|#)\s*(GOTCHA|BUG|WARN|HACK|NOTE|TODO)\s*:\s*(.+?)\s*$',
    re.MULTILINE,
)

matches = []
for m in TAG_RE.finditer(src):
    tag = m.group(1).upper()
    text = m.group(2).strip()
    line = src[:m.start()].count('\n') + 1
    matches.append((tag, text, line))

if not matches:
    sys.exit(0)

# ─── Section classification for gotchas.md ──────────────────────────────────
# TODO: customize these keyword sets to match your project's gotchas sections.
# First match wins. Ordering matters.
CLASSIFIERS = [
    ('auth-rls',          ['rls', 'policy', 'auth.uid', 'security definer',
                           'service role', 'anon key', 'search_path',
                           'permission', 'role']),
    ('stripe-payments',   ['stripe', 'payout', 'webhook secret',
                           'payment', 'invoice', 'billing']),
    ('bullmq-workers',    ['bullmq', 'new worker', 'queue', 'redis',
                           'worker.on', 'job retry']),
    ('react-native-expo', ['expo', 'react native', 'react-native', 'safearea',
                           'expo-router', 'expo sdk']),
    ('nextjs-api',        ['next.js', 'nextjs', 'next/', 'server action',
                           'route handler', "'use server'", "'use client'",
                           'app router', 'route.ts']),
    ('testing',           ['test', 'vitest', 'jest', 'pytest', 'fixture', 'mock']),
    ('schema-database',   ['migration', 'schema', 'pg_', 'postgres', 'unique',
                           'foreign key', 'alter table', 'ddl']),
]

def path_prior(path):
    p = path.lower()
    if p.endswith('.sql') or '/migrations/' in p:
        return 'schema-database'
    if '/apps/mobile/' in p or '/mobile/' in p:
        return 'react-native-expo'
    if '/apps/api/' in p and ('worker' in p or 'queue' in p):
        return 'bullmq-workers'
    if '/apps/web/' in p or '/apps/admin/' in p:
        return 'nextjs-api'
    return None

def classify(text, path):
    haystack = (text + ' ' + path).lower()
    for section, keywords in CLASSIFIERS:
        if any(k in haystack for k in keywords):
            return section
    prior = path_prior(path)
    if prior:
        return prior
    return 'general'

GOTCHAS_SCAFFOLD = """# Development Gotchas & Lessons Learned

Auto-populated by hooks. Add entries manually or via `// GOTCHA:` / `-- GOTCHA:` comments.

## Schema & Database

<!-- anchor: schema-database -->

## Auth & RLS

<!-- anchor: auth-rls -->

## React Native & Expo

<!-- anchor: react-native-expo -->

## Next.js & API Routes

<!-- anchor: nextjs-api -->

## Stripe & Payments

<!-- anchor: stripe-payments -->

## BullMQ & Workers

<!-- anchor: bullmq-workers -->

## Testing

<!-- anchor: testing -->

## General

<!-- anchor: general -->
"""

def ensure_gotchas_file(gotchas_path):
    if os.path.exists(gotchas_path):
        return
    os.makedirs(os.path.dirname(gotchas_path), exist_ok=True)
    with open(gotchas_path, 'w') as f:
        f.write(GOTCHAS_SCAFFOLD)

def append_to_section(gotchas_path, section, bullet):
    ensure_gotchas_file(gotchas_path)
    with open(gotchas_path) as f:
        text = f.read()
    if bullet.strip() in text:
        return
    anchor = f'<!-- anchor: {section} -->'
    i = text.find(anchor)
    if i == -1:
        if section != 'general':
            return append_to_section(gotchas_path, 'general', bullet)
        return
    j = text.find('<!-- anchor:', i + len(anchor))
    if j == -1:
        new = text.rstrip() + '\n' + bullet + '\n'
    else:
        next_heading = text.rfind('\n## ', i, j)
        if next_heading == -1:
            new = text[:j] + bullet + '\n\n' + text[j:]
        else:
            new = text[:next_heading] + '\n' + bullet + text[next_heading:]
    with open(gotchas_path, 'w') as f:
        f.write(new)

def append_todo(todos_path, file_path, line, text):
    bullet = f'- [ ] `{file_path}:{line}` — {text}'
    if os.path.exists(todos_path):
        with open(todos_path) as f:
            existing = f.read()
        if bullet in existing:
            return
        if not existing.endswith('\n'):
            existing += '\n'
    else:
        existing = (
            '# TODOs\n\n'
            'Auto-captured from `// TODO:` / `-- TODO:` / `# TODO:` comments.\n'
            'Mark done by replacing `- [ ]` with `- [x]` and removing the entry\n'
            'once the underlying code no longer carries the TODO.\n\n'
        )
    with open(todos_path, 'w') as f:
        f.write(existing + bullet + '\n')

gotchas_path = 'docs/gotchas.md'
todos_path   = 'docs/todos.md'

for tag, text, line in matches:
    if tag == 'TODO':
        append_todo(todos_path, file_path, line, text)
    else:
        section = classify(text, file_path)
        prefix = '' if tag == 'GOTCHA' else f'**{tag}:** '
        bullet = f'- {prefix}{text} _(from `{file_path}:{line}`)_'
        append_to_section(gotchas_path, section, bullet)
PY

exit 0
