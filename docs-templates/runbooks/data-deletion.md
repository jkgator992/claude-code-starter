# Data deletion runbook

**Last drill:** never
**Review cadence:** quarterly, and whenever a new PII-storing table is added
**Owner:** <FILL IN — usually legal or compliance lead>

---

## When to use this runbook

- User submits a GDPR / PIPEDA / CCPA deletion request
- Parent requests deletion of minor's data (COPPA)
- Tenant offboards and requests full data deletion per contract
- Scheduled drill (quarterly minimum per `pre-launch-auditor` Tier 3)
- Legal hold is lifted on previously-preserved data

## Legal timelines to respect

- **GDPR:** 30 days to respond to deletion request (extendable once to
  60 days for complex cases with user notified)
- **PIPEDA:** no fixed timeline, but "reasonable time" — plan for 30 days
- **CCPA:** 45 days
- **COPPA:** parental deletion requests must be honored promptly; no
  statutory deadline but "in a reasonable time"

If any of these are about to be missed, escalate to legal immediately.

## Before executing deletion

- [ ] Verify requester identity (email on file matches, account access
      confirmed, or legal documentation of relationship for minors)
- [ ] Check for active legal holds — if any, STOP and escalate
- [ ] Confirm which jurisdiction applies (determines scope of deletion)
- [ ] Confirm whether deletion is partial (specific data) or total
      (account closure)
- [ ] Record the deletion request in your compliance log with request ID,
      timestamp, requester, and scope

## Data map (must be current)

Before deletion can be executed, you must know what PII exists and where.
This section MUST be kept in sync with the schema — update it whenever a
new PII-storing table or external processor is added.

<FILL IN on first setup — this is a worked example for Oobi-like stack>

### First-party storage (your databases and storage)

| Location | What | Hard-delete path |
|---|---|---|
| `public.users` | email, name, phone, auth_user_id | Delete row; cascade fires |
| `public.user_profiles` | bio, avatar URL, birthday, preferences | Cascades from users |
| `public.user_push_devices` | device tokens | Cascades from users |
| `auth.users` | auth records, hashed passwords, session tokens | `supabase.auth.admin.deleteUser(auth_user_id)` |
| `public.redemptions` | user_id FK, location data | SET NULL on user_id (preserve for merchant audit) |
| `public.donations` | donor identity | SET NULL on donor_user_id; preserve financial record per IRS rules |
| `public.tickets` | user-authored support content | SET NULL on author; preserve content if others replied |
| `public.audit_log` | actor_user_id references | SET NULL; preserve event record |
| R2 bucket `<project>-participant-photos` | minor headshots (COPPA) | Delete object |
| R2 bucket `<project>-location-photos` (user-uploaded) | user avatars | Delete object |

### Third-party processors

| Service | What's there | Deletion path |
|---|---|---|
| Supabase Vault | Encrypted secrets referencing user | Delete via `rotateIntegrationSecret` with empty value |
| Stripe | Customer object, payment methods, invoices | `stripe.customers.del()`; invoices preserved per IRS |
| Resend | Contact in sending lists | Resend API: remove contact |
| OneSignal | Push subscription | OneSignal API: delete external_user_id |
| Twilio | SMS message history | Twilio API: redact messages (cannot delete) |
| Sentry | Error events with user context | Sentry API: redact user identifiers; events preserved |
| Cloudflare R2 | Objects uploaded by user | Delete per bucket listing above |
| Anthropic | API calls with user data | Not user-identifiable; no action needed |

### What CANNOT be deleted (legal preservation)

- **Financial records** (invoices, payouts, tax forms) — IRS requires
  retention, typically 7 years
- **Audit log entries** — preserved for security and legal defense;
  actor_user_id SET NULL but event remains
- **Aggregated/anonymized analytics** — no user identity remains, out of
  scope for deletion
- **Backups within retention window** — deletion propagates as old
  backups age out (document the window: <N> days)

The requester must be informed of what cannot be deleted before executing.

## Execution — the `deleteUserAccount` Layer 1 operation

This project's implementation uses a shared workflow operation that
performs all the above in a single transaction where possible, with
async cleanup for third-party processors:

```typescript
// packages/database/operations/users/deleteUserAccount.ts
// See shared-workflows.md for signature
```

Invocation paths:

1. **User self-service** (from account settings):
   - User clicks "Delete my account"
   - Confirmation modal with clear list of what will be deleted
   - Operation called with actor = the user themselves
   - 30-day grace period (soft delete) before hard delete cron runs

2. **Admin-initiated** (from staff dashboard, in response to a request):
   - Staff has `can_delete_user_account` permission
   - Ticket created recording the request
   - Operation called with actor = staff member, reason = ticket ID
   - Optional: skip grace period with super-admin approval

3. **Parent-initiated** (COPPA):
   - Support ticket received, parental relationship verified manually
   - Staff uses admin flow above with reason = "COPPA parental request"
   - Immediate hard delete (no grace period) — required by COPPA

## Drill procedure (run quarterly)

Pick a test account with realistic data:

1. Create a test account in staging with: user row, profile, 3
   redemptions, 1 donation, 2 photos uploaded, push device registered,
   5 support ticket messages
2. Run `deleteUserAccount` via admin dashboard with that user's ID
3. Verify every row in the data map above is either deleted or has PII
   redacted
4. Verify third-party processors were called (check Stripe customer gone,
   Resend contact removed, OneSignal subscription deleted, Sentry events
   redacted)
5. Verify the financial record (donations → invoices) still exists but
   no longer references the user by identity
6. Verify `audit_log` has a `hard_delete` entry recording the deletion
7. Time the end-to-end process. Target: under 15 minutes for staff-
   initiated deletion.

Document in the drill log.

## Reporting to the requester

Within the legal timeline, respond to the requester with:

- Confirmation the deletion was executed
- List of what was deleted (in plain language, from the data map)
- List of what was preserved and why (financial records, audit log)
- Expected timeline for backups to age out of retention
- A point of contact for follow-up questions

Template for the email lives at `<FILL IN — e.g., docs/templates/deletion-confirmation.md>`.

## Drill log

<!-- Append one line per drill. Most recent at top. -->

- _(no drills yet)_

## Related runbooks

- `docs/runbooks/incident-response.md`
- `docs/runbooks/backup-restore.md` (backups are part of retention chain)

## External references

- <FILL IN links to your data processing agreement, privacy policy,
  compliance attorney's contact info>
