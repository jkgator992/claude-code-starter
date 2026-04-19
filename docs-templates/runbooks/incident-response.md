# Incident response runbook

**Last reviewed:** never
**Review cadence:** quarterly, after every incident, and when on-call
rotation changes
**Owner:** <FILL IN — usually engineering manager or on-call lead>

---

## When to use this runbook

A production incident. Defined broadly:

- Service is down or significantly degraded for real users
- Data loss or corruption suspected
- Security breach suspected
- Third-party outage affecting critical functionality
- Billing / payment processing disrupted

If you're unsure whether it's an incident, declare it. Stand-down is
cheap; missed incident is expensive.

## Severity levels

- **SEV-1** — user-facing outage or data loss. All hands. Page everyone.
- **SEV-2** — degraded service, workarounds exist. Page on-call.
- **SEV-3** — isolated bug or minor degradation. Ticket, not a page.
- **SEV-4** — cosmetic or internal-only. Just a ticket.

Start with the highest severity that might apply and downgrade as you
learn more. Never upgrade silently — if you change severity, say so on
the incident channel.

## First 5 minutes

Whoever first notices the incident:

1. **Declare the incident.** Post in `#incidents` (or equivalent):
   ```
   🚨 INCIDENT SEV-?

   What: <one-sentence description>
   When noticed: <time>
   Who noticed: <n>
   Current guess at scope: <blast radius>

   I am incident commander until relieved.
   ```
2. **Start a timeline.** Open a doc or channel thread. Every significant
   action or finding gets a timestamped note. Don't trust memory — under
   stress, memory loses detail fast.
3. **Page the right people.** Use severity to decide:
   - SEV-1: on-call engineer, on-call lead, engineering manager, CEO/CTO
     if customer impact is material
   - SEV-2: on-call engineer, on-call lead
   - SEV-3: on-call engineer
4. **Assess user impact.** How many users affected? Which workflows? Is
   money at risk?

## The roles

In an incident larger than one person can handle, split roles explicitly.
Two people can wear the same hat; nobody wears no hat.

- **Incident Commander (IC)** — runs the incident. Decides direction.
  Does not debug. Keeps the timeline. Delegates.
- **Ops lead** — executes technical actions (rollbacks, restores,
  deploys). Reports back to IC.
- **Comms lead** — handles status page, user comms, internal updates,
  executive briefings. Drafts and sends everything externally-visible.
- **Scribe** — maintains the timeline doc. Captures what's tried, what
  works, what doesn't.

One person can wear multiple hats in a small incident. At SEV-1, splitting
is mandatory.

## Standard diagnostic steps

Before making changes, understand what's happening:

1. **Check Sentry** — error spike? new errors? stack traces point where?
2. **Check Supabase dashboard** — DB CPU, active connections, slow
   query log
3. **Check Upstash dashboard** — Redis OK? queue depth exploding?
4. **Check Railway** — API service healthy? memory? CPU? recent deploy?
5. **Check Vercel** — web/admin healthy? recent deploy? build status?
6. **Check third-party status pages:**
   - Supabase: status.supabase.com
   - Stripe: status.stripe.com
   - Cloudflare: cloudflarestatus.com
   - OneSignal: status.onesignal.com
   - Resend: resend-status.com
   - Anthropic: status.anthropic.com
   - AWS (if relevant): status.aws.amazon.com
7. **Check `api_events` table** (if your project uses one) for a surge
   in outbound failures to a specific service

## Common incident playbooks

### Playbook: third-party outage

Symptom: Stripe / Resend / OneSignal / etc. returning 5xx or timing out.

1. Confirm on the vendor's status page
2. If confirmed: disable non-critical calls to that service (feature
   flags), retry critical calls with exponential backoff
3. User-facing messaging: "We're experiencing an issue with <service>.
   <Specific workflow> is temporarily unavailable. We're monitoring."
4. Do NOT roll back your own deploy — it's not your bug
5. Monitor vendor status. When they recover, flush any queued work.

### Playbook: bad deploy

Symptom: error rate spike immediately after a deploy.

1. Sentry should show the spike starting at deploy time
2. See `docs/runbooks/rollback.md` — execute application rollback
3. Root-cause the bad deploy after service is restored, not during

### Playbook: database issue

Symptom: DB CPU pegged, slow queries piling up, connection pool exhausted.

1. Check for a runaway query — Supabase dashboard → slow query log
2. Check for a bad migration if one landed recently
3. Check for missing indexes on newly-added filter columns
4. Short-term mitigation: kill the worst offender query, scale the pool
   if provider allows
5. If it's a data-corruption issue rather than performance: see
   `docs/runbooks/backup-restore.md`

### Playbook: security incident

Symptom: leaked credential, suspicious access patterns, unexpected data
modifications.

**This is a different runbook than the others.** You have both a
technical problem and a legal/compliance problem.

1. **Don't delete evidence.** Before mitigating, snapshot logs and
   audit trail
2. **Isolate.** Rotate the compromised credential. Revoke sessions if
   needed
3. **Assess blast radius.** What could the attacker have read/written?
4. **Notify legal immediately.** Breach notification timelines are strict
5. **Do NOT go public until legal clears comms.** Even an internal
   all-hands message is sensitive at this stage
6. Continue standard IR procedure with heightened record-keeping

### Playbook: data loss

See `docs/runbooks/backup-restore.md`. Summary: confirm scope, decide
partial vs. full restore, get a second person, execute.

## User communication

When users are affected, they deserve to know:

- **Status page** — update within 10 minutes of incident declaration
  for SEV-1 and SEV-2. Keep it updated throughout.
- **In-app banner** — consider for prolonged SEV-1s. Flip via feature flag.
- **Email** — for SEV-1s lasting >1 hour or data-related incidents, send
  a notification via Resend. Pre-approved templates live at
  <FILL IN — e.g., docs/templates/incident-comms.md>.
- **Social** — only via comms lead or CEO, never spontaneously from
  engineering.

Tone: direct, specific, honest. "We're experiencing X. Users are seeing
Y. We expect resolution by Z. We'll update at <time>."

Avoid: "minor issue," "some users," "we're looking into it." Users hear
this as "you don't know what's happening."

## Resolution

- [ ] Confirm the fix worked — monitor for 15-30 minutes before declaring
- [ ] Update status page to resolved
- [ ] Send final user communication if one was promised
- [ ] Lift feature flag workarounds
- [ ] Thank the team in the incident channel
- [ ] Schedule post-mortem within 48 hours (SEV-1, SEV-2) or 1 week
      (SEV-3)

## Post-mortem

Blameless. Focus on systemic causes, not individual mistakes.

Template: <FILL IN — link to your post-mortem template or create one>

Required sections:

- Timeline (from the scribe's notes)
- Root cause (not "someone made a mistake" — "the system allowed a
  mistake to cause this outcome")
- What went well (protective factors to preserve)
- What went poorly (gaps to close)
- Action items with owners and due dates
- Prevention: new tests, new monitoring, new runbook entries

Action items are tracked in Jira until closed. Re-review every 30 days
until all are done.

## Vendor contacts

Keep this list current. Contacts get stale fast.

<FILL IN on first setup:>

- **Supabase support:** <email/portal>, severity-1 escalation <phone>
- **Stripe support:** dashboard → help, phone <number>
- **Cloudflare support:** dashboard → help; enterprise plan has phone
- **OneSignal:** email support@onesignal.com
- **Resend:** email support@resend.com
- **Railway:** Discord #support, email
- **Vercel:** dashboard → help; Pro/Enterprise has priority
- **Anthropic:** api.anthropic.com/help
- **Legal counsel (for breach/data):** <name + phone>
- **Insurance (for cyber):** <policy # + contact>

## Quarterly review checklist

- [ ] Vendor contact list current
- [ ] Severity rubric still matches actual incident patterns observed
- [ ] Runbook links all work
- [ ] On-call rotation documented and people know who's on
- [ ] Post-mortem action items from recent incidents all closed or
      explicitly deferred
- [ ] This runbook's "Last reviewed" date updated

## Related runbooks

- `docs/runbooks/backup-restore.md`
- `docs/runbooks/rollback.md`
- `docs/runbooks/data-deletion.md`
