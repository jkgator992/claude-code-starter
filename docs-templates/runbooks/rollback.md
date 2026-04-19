# Rollback runbook

**Last drill:** never
**Review cadence:** quarterly, or after any rollback incident
**Owner:** <FILL IN>

---

## When to use this runbook

- A production deploy introduced a bug that's actively hurting users
- A deploy broke something subtle that didn't surface until traffic
  hit it
- Scheduled drill (quarterly minimum per `pre-launch-auditor` Tier 3)

## Before you roll back

Always consider forward-fix first:

- Is the fix obvious and <15 minutes away? Forward-fix may be faster
  than rollback and avoids rollback risk
- Is the bug isolated to one feature you can disable via feature flag?
  Flip the flag; no rollback needed
- Is there a data migration involved? **Rollback may be impossible
  without data loss.** Forward-fix is usually the only safe option

Rollback if:
- Bug is causing active data loss / corruption
- Users cannot access core functionality
- Security vulnerability actively being exploited
- Forward-fix ETA > 30 minutes and impact is broad

## What can be rolled back

<FILL IN on first setup — this is project-specific>

- **`apps/api`** on Railway: one-click revert to previous deployment via
  Railway dashboard. Takes ~30 seconds to start rolling; ~2 minutes to
  fully healthy.
- **`apps/web`** and **`apps/admin`** on Vercel: "Instant Rollback" from
  the Deployments view. Takes ~10 seconds.
- **`apps/mobile`**: cannot hot-rollback — users have the old/new binary.
  EAS Update for JS-only changes (takes ~5 minutes to push, users get
  on next app launch). For native changes, resubmit previous version to
  TestFlight/Play Console (hours to days).
- **Database migrations**: require an explicit down-migration or PITR
  restore — see `backup-restore.md`. Rollback is NOT automatic.

## Rollback procedure by layer

### Application rollback (Railway + Vercel)

Fastest path. Safe as long as the new code didn't write data in a format
the old code can't read.

1. Identify the last known-good deployment:
   - Check Sentry for when errors started spiking
   - Check Railway/Vercel deployment history for the immediately prior
     deploy
2. Confirm the previous deployment has no breaking DB migrations between
   then and now. If migrations landed, STOP — see Database rollback.
3. Roll back:
   - Railway: Dashboard → apps/api → Deployments → `...` on previous →
     "Redeploy this version"
   - Vercel: Dashboard → Deployments → click previous → "Promote to
     Production"
4. Verify:
   - [ ] Sentry error rate returns to baseline within 5 minutes
   - [ ] Critical workflows smoke-tested (one of each: signup, core user
         action, payment)
   - [ ] On-call confirms "incident resolved"
5. Revert the bad commit on main (so main stays consistent with prod):
   ```bash
   git revert <bad-commit-sha>
   git push origin main
   ```
   This creates a forward revert commit — safer than force-push.

### Mobile rollback (JS-only — EAS Update)

For JS-only regressions, EAS Update pushes a new JS bundle to installed
apps without a store resubmit.

1. Identify the last known-good commit on the mobile branch
2. `eas update --branch production --message "Revert <bad-feature>"
   --ref <good-commit-sha>`
3. Verify via the EAS dashboard that the update published
4. Expect propagation: most users get it on next app launch; force a
   check with `Updates.checkForUpdateAsync()` in-app if the bug is severe

### Mobile rollback (native changes)

No hot rollback. Resubmit previous version:

1. Find the previous EAS build in the dashboard
2. Submit it to TestFlight/Play Console as an urgent update
3. Expect Apple review: 4-24 hours. Google: usually <2 hours but variable
4. In-app, if the bug is severe, consider remote-flag-disabling the
   broken feature so users with the new version get degraded function
   instead of crashes

### Database migration rollback

This is the dangerous one. Three options, in preference order:

**Option A — Down migration (if you wrote one).**
Your project <SHOULD / DOES NOT> write down migrations. If it does:

```bash
npx supabase migration down  # or equivalent
# Verify schema is back to expected state
npm run db:types             # regenerate types
```

Only safe if the down migration was tested and doesn't involve destructive
data changes.

**Option B — Forward-fix migration.**
Instead of rolling back, write a new migration that corrects the state.
Safer than rollback for most cases. See `docs/gotchas.md` for schema
patterns.

**Option C — Point-in-time restore.**
Restore the entire DB to before the bad migration landed. Loses all data
written since. See `backup-restore.md`.

## Post-rollback

- [ ] Incident channel updated with resolution time
- [ ] Status page updated (if public-facing)
- [ ] Users notified (if they experienced the bug)
- [ ] Root cause ticket filed in Jira
- [ ] Post-mortem scheduled within 48 hours
- [ ] Add the missed case to the test suite so it can't regress

## Scheduled drill procedure (run quarterly)

Rollback drills build the muscle memory that matters during a real
incident. Don't skip them.

1. Pick a staging deploy from the last week
2. Execute each rollback procedure (Application, then simulate the
   others — don't actually resubmit mobile builds or restore DB in a drill)
3. Time each procedure end-to-end. Record in the drill log below.
4. Note anything that was unclear in this runbook. Update the runbook.

## Known rollback gotchas

<FILL IN as you discover them. Examples:>

- Service-role key used in recent deploy but not in previous: rollback
  fails if the env var is still set (drift). Verify env var parity
  between current and target deployments first.
- Webhook URL changed: Stripe/Resend/etc. still send to new URL; rolled-
  back code doesn't have handler. Revert webhook URLs first.
- Feature flags enabled in the bad deploy may need to be disabled before
  rollback to prevent the rolled-back code from hitting new flag paths.

## Drill log

<!-- Append one line per drill. Most recent at top. -->

- _(no drills yet)_

## Related runbooks

- `docs/runbooks/backup-restore.md` — database-level rollback
- `docs/runbooks/incident-response.md` — general incident coordination
