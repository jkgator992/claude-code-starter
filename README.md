# Claude Code Starter Kit

A reusable, opinionated starter for dropping a full Claude Code harness into
any codebase — hooks, agents, skills, docs templates, and (optionally) the
[Octopus](https://github.com/nyldn/claude-octopus) multi-LLM plugin.

## What you get

- **24 production hooks** — secret blockers, format-on-write, audit logging,
  pre-commit gate, session resume, auto-changelog, and framework-specific
  guards for Supabase / BullMQ / Next.js.
- **12 specialist agents** — architect, backend-architect, frontend,
  mobile-maestro, security, qa-tester, qa-automation, rls-auditor,
  layer1-enforcer, devops, plus **optional** dispatcher and
  pre-launch-auditor when you enable parallel dev / auditor features.
- **5 skills** — operation templates, RLS test patterns, error taxonomy,
  learning capture, QA runbook.
- **6 slash commands (optional)** — when parallel dev is enabled: ticket-start,
  ticket-close, worktrees, backfill-tickets, batch-plan, triage-bug.
- **6 runbook templates (optional)** — when auditor is enabled: backup-restore,
  rollback, data-deletion, incident-response, bug-intake, parallel-development.
- **k6 load test template (optional)** — Tier 2 pre-launch auditor gate.
- **Docs scaffolding** — `gotchas.md`, `violations.md`, `traceability.md`,
  `completion-log.md`, `api-reference.md`, `test-registry.csv`.
- **3 settings presets** — `full`, `supabase`, `minimal`.
- **Optional Octopus integration** — multi-LLM orchestration via Codex,
  Gemini, and Copilot.

## Quick start

```bash
git clone https://github.com/<you>/claude-code-starter.git
cd /path/to/your/project
bash /path/to/claude-code-starter/install.sh
```

The installer will:

1. Ask 10 questions about your project (name, stack, Supabase y/n, test
   runner, package manager, directory layout).
2. Show a diff before overwriting any existing file; you choose
   **overwrite / merge / skip** per file.
3. Copy only the hooks/agents/skills that match your stack.
4. Stamp `CLAUDE.md` and `AGENTS.md` templates with your answers (every
   slot you leave blank becomes a `TODO:` marker).

Alternatively, paste the contents of [INSTALL.md](./INSTALL.md) into Claude
Code and let Claude run the wizard for you.

## Octopus (multi-LLM) — optional

[Octopus](https://github.com/nyldn/claude-octopus) is a plugin that lets
Claude Code orchestrate Codex, Gemini, and Copilot in parallel. The starter
kit can install it for you, but you run the setup yourself.

Three-step install:

1. **Terminal install** (not inside Claude Code):

   ```bash
   bash plugins/install-plugins.sh
   ```

   This runs:

   ```
   claude plugin marketplace add https://github.com/nyldn/claude-octopus.git
   claude plugin install octo@nyldn-plugins
   ```

2. **Claude Code setup** — open Claude Code in your project and run:

   ```
   /octo:setup
   ```

   The wizard installs providers, configures auth, and sets up the RTK
   (ready-to-kick) toggles.

3. **Claude-only mode works immediately.** You can stop after step 2 and
   use `/octo:auto` as a smart router on top of Claude alone.

4. **Optional: add Codex / Gemini / Copilot** for true multi-LLM parallel
   work. Re-run `/octo:setup` and opt-in to each provider you want.

> Octopus installs at **user level**, not project level. The starter's
> `plugins/install-plugins.sh` script handles the install — no Octopus
> files are committed into your repo.

## The 10 questions

The wizard asks (in order):

1. **Project name** — used in `CLAUDE.md` title and imports.
2. **One-sentence description** — stamped into `CLAUDE.md` intro.
3. **Tech stack** — Next.js / React Native / Node / Python / other.
4. **Using Supabase?** — yes/no. Turns on RLS auditor, Layer 1 enforcer,
   migration hooks, schema docs sync.
5. **Test runner** — Vitest / Jest / Pytest / other.
6. **Package manager** — npm / yarn / pnpm.
7. **Auto-detect directory structure** — yes runs `ls` against your repo
   and tries to match common layouts (monorepo vs single app).

8. **Enable parallel dev system?** — yes/no. Installs the `dispatcher` agent,
   6 slash commands for Jira ticket lifecycle (`/ticket-start`, `/ticket-close`,
   `/worktrees`, `/backfill-tickets`, `/batch-plan`, `/triage-bug`), and a
   migration-lock hook that enforces one-worktree-per-migration across
   parallel sessions. Opt in if you use Jira and want git-worktree-based
   parallel development.
9. **Enable pre-launch auditor + runbooks?** — yes/no. Installs the
   `pre-launch-auditor` agent (3 tiers: pre-merge static, pre-promotion
   dynamic, quarterly policy), 6 operational runbook templates, and a k6
   smoke load test template. Opt in for production-bound projects.
10. **Existing project?** — yes/no. Tells the installer this isn't a
    fresh scaffold. When combined with the auditor, writes a
    `.claude/pre-launch-config.json` enabling grandfather mode so the
    auditor only blocks on findings in NEW code (files changed after the
    current HEAD) while still tracking legacy findings.

Every answer becomes a template substitution. Questions you skip leave a
`TODO:` marker in the output so you can fill them in later.

## Layout

```
claude-code-starter/
├── README.md                ← this file
├── INSTALL.md               ← paste-into-Claude-Code install instructions
├── install.sh               ← one-command installer (runs wizard + copies)
├── wizard.sh                ← just the 7-question wizard, no side effects
├── templates/               ← CLAUDE.md / AGENTS.md with TODO: markers
├── hooks/
│   ├── universal/           ← work on any project
│   ├── supabase/            ← Supabase-specific
│   ├── bullmq/              ← BullMQ-specific
│   └── nextjs/              ← Next.js-specific
├── agents/
│   ├── universal/
│   ├── supabase/
│   ├── nextjs/
│   ├── react-native/
│   └── node/
├── skills/                  ← 5 SKILL.md files (always installed)
├── commands/
│   └── universal/           ← 6 optional slash commands (parallel dev)
├── docs-templates/          ← gotchas.md, violations.md, etc.
│   └── runbooks/            ← 6 optional operational runbook templates
├── templates/tests/load/    ← optional k6 smoke load test template
├── settings-templates/      ← full / supabase / minimal settings.json
└── plugins/
    └── install-plugins.sh   ← Octopus installer
```

## Overwrite policy

The installer **never** overwrites a file silently. For every file in the
target that already exists:

1. It shows a unified diff of the incoming content vs what's there.
2. You pick:
   - `o` — overwrite (replace)
   - `m` — merge (open both files in `$EDITOR` side-by-side so you can
     hand-merge, then continue)
   - `s` — skip (leave the existing file)
3. The installer logs every decision to `.claude-starter.log` in your
   project so you can re-run or audit.

## Requirements

- `bash` 4+, `jq`, `git`, and either `diff` or `colordiff` on your PATH.
- For Octopus: `claude` CLI (Claude Code) must be installed and logged in.

## License

MIT. Do whatever you want — this is infrastructure glue, not a product.

## Credits

Hook patterns, agent personas, and skill scaffolds were extracted from
[oobi](https://github.com/) (a regional savings & fundraising platform
monorepo) and generalized. If you find a bug or have a better hook,
please send a PR.
