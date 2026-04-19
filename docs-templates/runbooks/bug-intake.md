# Bug intake runbook

**Last reviewed:** never
**Review cadence:** after each new bug intake channel added, and quarterly
**Owner:** <FILL IN — usually support lead or PM>

---

## When to use this runbook

Any time a user-reported bug enters your system. Five channels to watch:

1. **In-app "Report a Problem"** — writes to `tickets` / `location_change_requests`
2. **Support email** — Gmail inbox monitored by support team
3. **App Store reviews** — occasionally contain actionable bug reports
4. **Direct (Slack DM, phone call, text message)** — you or a staff
   member receives the report, transcribes into a ticket
5. **Social media / community** — rare but real

This runbook covers how to move a report from any of those channels into
`/triage-bug` and then into engineering.

## The flow, at a glance

```
User report
    ↓
Support acknowledges within 1 business day
    ↓
Triage: is this a bug, a feature request, or a user error?
    ↓
If bug: /triage-bug draft → human review → create Jira Bug
    ↓
Engineering: /batch-plan picks up by severity → /ticket-start → fix → ship
    ↓
Support notifies user: "Fixed in build X"
    ↓
User confirms resolution → close original support thread
```

## Step 1: Acknowledgment (support, within 1 business day)

Every user who reports a bug gets an acknowledgment within one business
day. Not a fix, not a commitment — just "we heard you, we're looking."

Template:

> Thanks for the report. We've logged this and our engineering team will
> investigate. We'll follow up with an update within <N> business days.
> Your reference: <ticket or email ID>.

If the bug is clearly critical (data loss, payment wrong, account locked),
acknowledge within 1 hour and route to on-call immediately.

## Step 2: Reproducibility check (support, 1-2 hours)

Before triage, support tries to reproduce. Three questions:

1. **Can you reproduce it reliably?** — If yes, capture exact steps.
2. **Does it happen for other users?** — Check if similar reports exist
   or if it's isolated to this account.
3. **Is there data to attach?** — screenshots, error messages, timestamps,
   device/OS, account context.

Four outcomes:

- **Reproducible + bug** → move to Step 3 (triage)
- **Reproducible + not a bug** → user education response; document the
  confusion for UX to consider (may indicate a design bug even if not a
  code bug)
- **Not reproducible + likely bug** → ask the user for more detail;
  document what you need; stay in Step 2 until either reproducible or
  abandoned
- **Clear user error** → explain to user, close; no Jira ticket needed

If uncertain between outcomes, default to "move to Step 3" — engineering
triage can distinguish faster than support debate.

## Step 3: Run `/triage-bug`

In a Claude Code session with the repo checked out:

```
/triage-bug --source <ticket:SCRUM-N | email:thread-id | paste>
```

Follow the prompts. The command produces a draft Jira Bug ticket with
inferred severity, file paths, test cases.

**Always review before creating.** `/triage-bug --apply` exists for power
users but for a small team it's a footgun. Take the 90 seconds to read
the draft.

What to look at during review:

- **Summary** — does it describe the symptom precisely? Edit if vague.
- **Severity** — does it match your gut? Architect is conservative; if
  your experience says this is worse than what architect picked, escalate.
  If your experience says lower, de-escalate.
- **Files touched** — are the candidate files plausible? If architect put
  `apps/api/workers/pdf-generate.ts` but the bug is about push
  notifications, architect missed. Fix the paths before creating.
- **Duplicates** — do any of the flagged candidates actually match? If
  yes, link instead of creating new.

## Step 4: After the ticket exists

`/triage-bug` handles most of this automatically:

- Jira ticket created with status `To Do`
- User/original-report notification drafted (for you to send)
- Audit trail entry in `docs/bug-triage-log.md`

What YOU do manually:

- Send the user acknowledgment update: "We've triaged this as <severity>.
  Expected fix timeline: <N weeks based on severity>. We'll update you
  when it ships."
- Do NOT promise a specific date — bugs slip. Promise a status update
  instead.

## Severity → response time targets

| Severity | Acknowledgment | Fix target | Communication |
|---|---|---|---|
| Critical | 1 hour | 24 hours | Daily updates to user |
| High | 4 hours | 1 week | Updates every 48h |
| Medium | 1 business day | 2 weeks | Update on fix |
| Low | 1 business day | Next sprint or "someday" | Update on fix |

These are targets, not contracts. Real-world slippage happens. When it
does, update the user proactively — silence feels worse than a delay.

## Step 5: During the fix

Engineer working the ticket follows the parallel dev system normally
(`/ticket-start` → dispatcher → fix → audit → close). One rule specific
to bugs:

**The regression test must fail BEFORE the fix lands.**

This is non-negotiable. If the regression test you wrote passes on the
current broken code, your test is wrong — it's not actually testing the
reported scenario. Rewrite until it fails, then make the fix, then watch
it pass.

`qa-tester` in the dispatcher's Phase 3 review will check for this.

## Step 6: After the fix ships

- Notify the reporting user:

  > The issue you reported (ref: XXXX) has been fixed in <version/build>.
  > You should see <expected behavior> now. If you still experience the
  > problem, please reply to this and we'll reopen.

- Wait for user confirmation (give them 7 days)
- Close the original support thread as resolved
- If user reports the fix didn't work, do NOT just close and move on —
  reopen the Jira bug or create a new one with the user's continued
  report as evidence

## Special cases

### Critical bug reported outside business hours

Page on-call immediately. Skip the 1-hour acknowledgment — on-call
acknowledges directly to the user. On-call decides whether to hotfix
now or defer to morning based on blast radius.

### Security-sensitive bug report

Don't triage this via the normal flow. Don't create a public Jira ticket
with exploit details in the description. Instead:

1. Acknowledge receipt privately to reporter
2. Create a Jira Bug with minimal public description ("Security issue
   under investigation") and move it to a private security board if one
   exists
3. Follow the security incident runbook (`docs/runbooks/incident-response.md`)
   if the bug is actively exploitable
4. Once fixed and deployed, write a public postmortem if appropriate;
   coordinate disclosure timing with legal

### Duplicate report after ticket already exists

Link the new report to the existing Jira ticket. Add to the ticket's
description: "Also reported by <user handle> on <date>." This shows
engineering the bug's user-impact breadth and helps prioritize.

### User won't provide enough detail

Some reports are vague and the user won't or can't clarify. Don't force
triage on an unreproducible report — it burns engineering time and
produces unhelpful speculation.

Options:

- Add to a "pending more info" list, revisit weekly
- Ask for a screen recording, browser console log, or specific timestamp
- Close as "cannot reproduce" after two failed follow-ups; reopen
  immediately if anyone else reports the same

### The user reports something that's not a bug — it's a feature gap

Don't file as a Bug. File as a Story or Feature Request. `/triage-bug`
will usually catch this in Step 3 (architect will say "this isn't
broken, it's unimplemented") and flag it. Your response to the user is
different too: "Thank you, we've added this to our feature tracker. No
timeline promise, but we appreciate the signal."

## Metrics to track (monthly review)

- **Intake volume** by channel — which channel is under-served
- **Triage accuracy** — severity at triage vs. severity at close (should
  be close; big drift means triage is miscalibrated)
- **Time to acknowledge** by severity — target vs. actual
- **Time to close** by severity — target vs. actual
- **Reopen rate** — bugs closed then re-reported within 30 days; high
  number means the fix wasn't durable

Log these to `docs/bug-metrics-monthly.md` for the monthly review.

## Anti-patterns to avoid

- **Treating every user complaint as a bug** — many are user errors,
  feature requests, or expectation mismatches. Triage ruthlessly.
- **Promising fix dates** — bugs slip. Promise communication, not
  calendar dates.
- **Closing "cannot reproduce" too fast** — give the user two chances to
  provide more info. Closing prematurely makes them feel dismissed.
- **Creating a separate Jira ticket per duplicate report** — link to
  existing; this keeps the signal clean.
- **Skipping the regression test** — shipping a "fix" without a test
  that locks in the fix is how bugs come back.

## Review log

<!-- Append one line per quarterly review. Most recent at top. -->

- _(no reviews yet)_

## Related

- `.claude/commands/triage-bug.md` — the triage command itself
- `docs/runbooks/incident-response.md` — for critical bugs
- `docs/bug-triage-log.md` — auto-written by `/triage-bug`
