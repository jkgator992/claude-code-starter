# Installing claude-code-starter

There are three ways to install. Pick one.

---

## Option A — One command (recommended)

```bash
cd /path/to/your/project
bash /path/to/claude-code-starter/install.sh
```

The installer runs the wizard, shows a diff for every existing file, and
lets you choose overwrite / merge / skip per file. See [README.md](./README.md)
for the full overwrite policy.

---

## Option B — Paste this into Claude Code

If you'd rather have Claude orchestrate the install for you, open Claude
Code in your project root and paste everything in the fenced block below.
Claude will run the wizard, ask you the 7 questions, and apply the
selected files with a diff check on each overwrite.

````
You are installing claude-code-starter into the current repository.

The starter kit lives at: ~/claude-code-starter
(or: $CLAUDE_CODE_STARTER — check this env var first; if unset, use
~/claude-code-starter, and if that's missing, ask the user for the path.)

Steps:

1. Run `bash $STARTER/wizard.sh` to collect the 7 answers. Capture stdout
   to a variable — it emits a JSON blob on the last line.

2. For each file the wizard selects:
   - If the target doesn't exist, copy it.
   - If it exists, show a unified diff (`diff -u old new`) and ask the user:
     overwrite / merge / skip.
     - `merge` = open $EDITOR with both versions; after the user saves,
       continue to the next file.
     - `skip` = leave the existing file untouched.

3. Stamp every `TODO:` marker in the installed templates with the wizard
   answers where possible. Leave unresolved TODOs in place so the user
   can audit.

4. Log every decision (install / skip / merge) to `.claude-starter.log`.

5. At the end, print a summary:
   - files installed
   - files skipped
   - unresolved TODOs (file:line)
   - next steps (especially Octopus setup — see step 6)

6. Octopus setup is NOT done automatically. Tell the user to:

   a) Exit Claude Code and run in their terminal:

      bash plugins/install-plugins.sh

   b) Then re-open Claude Code and run:

      /octo:setup

   This order matters because `claude plugin install` needs to run
   outside an active Claude Code session.

Do not push to git. Do not commit. The user will do that themselves.
````

---

## Option C — Manual copy

If you want full control, copy individual pieces by hand.

```bash
# 1. Pick a settings preset
cp settings-templates/settings.full.json .claude/settings.json
# or settings.supabase.json / settings.minimal.json

# 2. Copy universal hooks
mkdir -p .claude/hooks
cp hooks/universal/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh

# 3. Copy stack-specific hooks (optional)
cp hooks/supabase/*.sh .claude/hooks/    # if using Supabase
cp hooks/bullmq/*.sh .claude/hooks/      # if using BullMQ
cp hooks/nextjs/*.sh .claude/hooks/      # if using Next.js

# 4. Copy agents you want
mkdir -p .claude/agents
cp agents/universal/*.md .claude/agents/
cp agents/supabase/*.md .claude/agents/     # if using Supabase
cp agents/nextjs/*.md .claude/agents/       # if using Next.js
# ... etc

# 5. Copy all skills (they're small and opt-in per-invocation)
mkdir -p .claude/skills
cp -R skills/* .claude/skills/

# 6. Copy docs templates
mkdir -p docs docs/tests
cp docs-templates/*.md docs/
cp docs-templates/tests/*.csv docs/tests/

# 7. Copy CLAUDE.md and AGENTS.md templates
cp templates/CLAUDE.md ./CLAUDE.md
cp templates/AGENTS.md ./AGENTS.md

# then hand-edit every `TODO:` marker in those two files.
```

---

## After install — Octopus plugin (optional)

Octopus adds multi-LLM orchestration (Codex / Gemini / Copilot alongside
Claude). It installs at the **user level**, not the project level, so the
starter does not commit any Octopus files.

**Step 1 — run in your terminal (not inside Claude Code):**

```bash
bash plugins/install-plugins.sh
```

This runs the two `claude plugin` commands below. They must be run from a
shell, not from inside Claude Code — the plugin host needs to restart.

```
claude plugin marketplace add https://github.com/nyldn/claude-octopus.git
claude plugin install octo@nyldn-plugins
```

**Step 2 — open Claude Code in your project and run:**

```
/octo:setup
```

The setup wizard:

- Detects which providers you have (Claude, Codex, Gemini, Copilot).
- Prompts for missing auth.
- Configures the RTK (ready-to-kick) toggles.
- Installs token-optimization presets.

**Step 3 (optional) — add more providers.**

Claude-only mode works out of the box after `/octo:setup`. If you want
parallel multi-LLM execution, re-run `/octo:setup` and enable Codex,
Gemini, or Copilot individually.

---

## Troubleshooting

- **`jq: command not found`** — install `jq` (`brew install jq` on macOS,
  `apt install jq` on Debian/Ubuntu). Many hooks parse Claude Code's
  JSON payload with `jq` and will silently skip if it's missing.
- **Hooks don't fire** — check `.claude/settings.json` exists, is valid
  JSON, and that hook scripts have `chmod +x`.
- **`claude plugin` command not found** — you need Claude Code CLI.
  Install from https://docs.claude.com/claude-code.
- **Octopus commands not showing** — restart Claude Code after running
  `plugins/install-plugins.sh`. Plugin discovery only happens at startup.
