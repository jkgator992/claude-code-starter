# Backup and restore runbook

**Last drill:** never
**Review cadence:** quarterly, or after any DB-level incident
**Owner:** <FILL IN>

---

## When to use this runbook

- Scheduled drill (quarterly minimum per `pre-launch-auditor` Tier 3)
- Suspected data loss or corruption incident
- Restoring a staging environment from a prod snapshot for testing
- Recovering from a bad migration

## Prerequisites

Before anything else, verify:

- [ ] You have admin credentials to the database hosting provider
      (Supabase dashboard, AWS RDS console, etc.)
- [ ] You have the current date of the most recent known-good backup
- [ ] If restoring production, you have an approver (on-call lead or
      engineering manager) — solo restores of prod are not allowed
- [ ] You have ~30-60 minutes of uninterrupted time for the drill

## What's backed up

<FILL IN on first setup — this is project-specific>

- **Database:** Supabase automatic daily backups (7-day retention on
  Pro plan, 30-day on Team/Enterprise). Point-in-time recovery within
  the retention window.
- **Object storage:** <FILL IN — e.g., Cloudflare R2 buckets, S3>.
  Lifecycle rules: <FILL IN>.
- **Secrets/Vault:** Supabase Vault entries backed up with the database.
  Infrastructure-level secrets (Railway/Vercel env vars) are NOT
  auto-backed up — exported manually to 1Password quarterly.
- **User-uploaded files:** <FILL IN — stored in R2/S3>. Retention: <FILL IN>.
- **What is NOT backed up:**
  - Local developer environments
  - In-flight BullMQ jobs (lost on Redis restart; jobs are designed to
    be idempotent and retryable)
  - Upstash Redis caches (rebuildable on demand)

## Scheduled drill procedure (run quarterly)

### 1. Pre-drill setup (5 minutes)

- Schedule a 60-minute window during low-traffic hours
- Notify on-call rotation
- Verify staging environment is in a known state (run full test suite)
- Take a staging snapshot right now so you can roll back the drill if
  it goes wrong

### 2. Identify restore target

Pick a point-in-time 24 hours in the past. Record:

- Backup timestamp: <to be filled during drill>
- Expected row counts for key tables at that time:
  - users: <count>
  - tenants: <count>
  - <other critical tables>: <counts>

### 3. Restore to staging

<FILL IN — exact commands for your hosting provider. Examples:>

For Supabase (PITR):
```bash
# Via dashboard: Database → Backups → Point in Time Recovery
# Select timestamp, confirm, wait for restore to complete (~5-15 min)
```

For self-hosted Postgres:
```bash
pg_restore --host=<staging-host> --dbname=<staging-db> \
  --clean --if-exists --no-owner --no-privileges \
  /path/to/backup.dump
```

### 4. Verify restore

- [ ] Row counts on key tables match pre-drill expectations
- [ ] Critical workflows work end-to-end (signup, primary user action,
      billing touchpoint)
- [ ] No errors in application logs during first 5 minutes post-restore
- [ ] Migrations are at the expected version (check `schema_migrations`
      or equivalent)
- [ ] RLS still enforces correctly (run RLS baseline test suite)

### 5. Restore the restore target (cleanup)

Roll staging back to its pre-drill state using the snapshot from step 1.

### 6. Document the drill

Update the "Last drill" field at the top of this file. Append to the drill
log below:

```
YYYY-MM-DD — <name> — duration Nm — outcome: success|issues
  Notes: <anything unexpected>
```

If anything went wrong, file a ticket to fix before the next drill.

## Emergency restore procedure (real incident)

This is different from the drill because you're racing the clock and
there's risk of making things worse.

### 0. STOP and get a second person

Do NOT perform an emergency restore alone. Page the on-call lead. Two
people, one to execute, one to verify each command before it runs.

### 1. Assess the scope

- What's broken? (data missing, data corrupted, wrong data, DB down)
- When did it start? (timestamp of last known-good state)
- What's the blast radius? (one table, one tenant, everything)

### 2. Decide: partial vs. full restore

- **Full restore** — entire DB rolled back to a prior point. Fast but
  destroys any legitimate writes since the restore point. Only for
  catastrophic corruption.
- **Partial restore** — restore to a side database, cherry-pick the
  affected rows/tables back to prod. Slower but preserves good data.
  Preferred unless corruption is too broad to identify.

### 3. Notify

Before executing anything destructive:

- [ ] Status page updated (if public-facing)
- [ ] Users notified (if downtime expected)
- [ ] Compliance/legal notified if PII may be affected
- [ ] Incident channel opened

### 4. Execute per decision above

Use the drill procedures as the base, modified for the specific scenario.

### 5. Post-incident

- [ ] All restored data verified
- [ ] Audit log reviewed for anything that happened during the incident
      window that needs follow-up
- [ ] Post-mortem scheduled within 48 hours
- [ ] This runbook updated with anything learned

## Recovery time objective (RTO) and recovery point objective (RPO)

<FILL IN on first setup:>

- **RTO** (how fast you can be back up): target <N> hours
- **RPO** (how much data you can afford to lose): target <N> minutes
  to <N> hours

If the actual incident exceeds these, escalate per incident response
runbook.

## Drill log

<!-- Append one line per drill. Most recent at top. -->

- _(no drills yet)_

## Related runbooks

- `docs/runbooks/incident-response.md` — general incident handling
- `docs/runbooks/rollback.md` — application (not database) rollback
- `docs/runbooks/data-deletion.md` — GDPR/PIPEDA purge procedures
