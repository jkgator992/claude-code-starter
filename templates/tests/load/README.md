# Load tests

Starter scripts for `pre-launch-auditor` Tier 2.

## Run against staging

```bash
# Install k6 first (macOS): brew install k6
# Install k6 first (other): https://grafana.com/docs/k6/latest/set-up/install-k6/

k6 run tests/load/smoke.k6.js
```

Or with overrides:

```bash
k6 run --env BASE_URL=https://staging.example.com \
       --env VUS=50 \
       --env DURATION=10m \
       tests/load/smoke.k6.js
```

## What gets tested

`smoke.k6.js` hits three workflow families:

1. **Public read** — anonymous endpoints, should be cacheable, fast
2. **Authenticated write** — placeholder until test-user seeding is in
   place (see TODO in script)
3. **Webhook rejection** — verifies unsigned webhooks return 401/403
   under load

## Targets

The script's thresholds enforce Tier 2 targets directly — k6 exits
non-zero if any threshold is missed, which makes it safe to wire into
CI as a gate before the staging-to-prod promotion.

- p95 read: <500ms
- p95 write: <1000ms
- Error rate: <0.5%

These match the defaults in `pre-launch-auditor.md` Tier 2 #5. If your
project needs different targets, edit both the script and the auditor
agent together.

## NEVER run against production

The script ramps to ~20 VUs hammering endpoints with minimal think-time.
Production will rate-limit you; if rate limits are misconfigured, you'll
wake up your on-call. Staging only.

## Next steps after first run

- [ ] Fill in `BASE_URL` default with your actual staging hostname
- [ ] Replace `/api/offers/public` with your real public read endpoint
- [ ] Replace `/api/<FILL IN>` write placeholder with a real authenticated
  write once test-user seeding exists
- [ ] Replace `/webhooks/<FILL IN>` with your real webhook path
- [ ] Wire into CI: run on the staging deploy post-success, block the
  prod promotion if it fails

## Expanding beyond smoke

`smoke.k6.js` is a 5-minute sanity check. For real capacity planning, add:

- `tests/load/soak.k6.js` — sustained 1+ hour run, catches memory leaks
- `tests/load/spike.k6.js` — sudden 10x traffic burst, tests autoscaling
- `tests/load/stress.k6.js` — ramp past capacity to find breaking point

Each has its own threshold profile. Only the smoke test should gate CI;
others are manual exercises before major releases.

## References

- k6 docs: https://grafana.com/docs/k6/latest/
- Thresholds: https://grafana.com/docs/k6/latest/using-k6/thresholds/
- Custom metrics: https://grafana.com/docs/k6/latest/using-k6/metrics/create-custom-metrics/
