// tests/load/smoke.k6.js
//
// Starter k6 load test for pre-launch-auditor Tier 2.
//
// What this does:
//   - Hits three critical-path workflows against staging
//   - Measures p95 latency, error rate, and sustains traffic for 5 minutes
//   - Exits non-zero if targets are missed (CI gate)
//
// What this does NOT do:
//   - Load-test authenticated-only workflows that require session setup
//     (TODO: add once you have a test-user seeding script)
//   - Simulate real user think-time (intentionally aggressive)
//   - Test production — NEVER run load tests against prod
//
// Usage:
//   k6 run tests/load/smoke.k6.js
//   k6 run --env BASE_URL=https://staging.<FILL IN> tests/load/smoke.k6.js
//   k6 run --env VUS=50 --env DURATION=10m tests/load/smoke.k6.js
//
// Expected Tier 2 targets (fail the run if any is missed):
//   - p95 < 500ms on read endpoints
//   - p95 < 1000ms on write endpoints
//   - Error rate < 0.5%
//   - Throughput sustained without queue depth runaway

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ─── Configuration ──────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || 'https://staging-api.<FILL IN>';
const VUS = parseInt(__ENV.VUS || '20');
const DURATION = __ENV.DURATION || '5m';

// ─── Custom metrics ─────────────────────────────────────────────────────
const readErrors = new Rate('read_errors');
const writeErrors = new Rate('write_errors');
const readDuration = new Trend('read_duration_ms');
const writeDuration = new Trend('write_duration_ms');

// ─── Test configuration ─────────────────────────────────────────────────
export const options = {
  scenarios: {
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: VUS },      // ramp to target
        { duration: DURATION, target: VUS },    // sustain
        { duration: '30s', target: 0 },         // ramp down
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // Tier 2 gates — fail the run if any is missed
    'http_req_failed': ['rate<0.005'],                         // <0.5% errors
    'read_duration_ms{type:read}': ['p(95)<500'],              // p95 read <500ms
    'write_duration_ms{type:write}': ['p(95)<1000'],           // p95 write <1s
    'read_errors': ['rate<0.005'],
    'write_errors': ['rate<0.005'],
  },
};

// ─── Test user pool (add to this as you add features) ───────────────────
// TODO: load from a file instead of inlining. For now, 10 synthetic VUs
// share these IDs — expected in a smoke test but not a real load test.
const TEST_USERS = [
  // Fill in with staging-seeded test user IDs or signed session tokens
  // { token: '...', userId: '...' },
];

// ─── Helpers ────────────────────────────────────────────────────────────
function authHeaders() {
  // When authenticated workflows are in scope, return an Authorization
  // header with a staging token. For now, the smoke test only hits
  // public read paths and anonymous write paths.
  return { 'Content-Type': 'application/json' };
}

// ─── Critical path 1: public read (feed / offers list) ──────────────────
function readFlow() {
  group('public_feed_read', () => {
    const res = http.get(`${BASE_URL}/api/offers/public?lat=35.2&lng=-80.8`, {
      headers: authHeaders(),
      tags: { type: 'read', endpoint: 'offers_public' },
    });

    readDuration.add(res.timings.duration, { type: 'read' });
    readErrors.add(res.status !== 200);

    check(res, {
      'status 200': (r) => r.status === 200,
      'body has offers array': (r) => {
        try {
          const body = JSON.parse(r.body);
          return Array.isArray(body.offers);
        } catch { return false; }
      },
    });
  });
}

// ─── Critical path 2: authenticated write (placeholder) ─────────────────
// Fill in when test-user tokens exist in staging
function writeFlow() {
  if (TEST_USERS.length === 0) {
    // Skip until the test-user seed is in place
    return;
  }

  const user = TEST_USERS[Math.floor(Math.random() * TEST_USERS.length)];

  group('authenticated_write', () => {
    const res = http.post(
      `${BASE_URL}/api/<FILL IN — e.g. /api/favorites>`,
      JSON.stringify({ /* payload */ }),
      {
        headers: {
          ...authHeaders(),
          Authorization: `Bearer ${user.token}`,
        },
        tags: { type: 'write', endpoint: 'favorite_toggle' },
      }
    );

    writeDuration.add(res.timings.duration, { type: 'write' });
    writeErrors.add(res.status >= 400);

    check(res, {
      'status 2xx': (r) => r.status >= 200 && r.status < 300,
    });
  });
}

// ─── Critical path 3: webhook endpoint (signature check, no processing) ─
// Loads the webhook handler's signature-verification path without
// sending valid signatures — measures how gracefully it rejects.
function webhookFlow() {
  group('webhook_signature_reject', () => {
    const res = http.post(
      `${BASE_URL}/webhooks/<FILL IN — e.g. /webhooks/stripe>`,
      JSON.stringify({ type: 'test', data: {} }),
      {
        headers: { 'Content-Type': 'application/json' },
        tags: { type: 'read', endpoint: 'webhook_reject' },
      }
    );

    // Expect 401 or 403 — the webhook must reject unsigned requests.
    // Anything else (especially 200) is a bug.
    readDuration.add(res.timings.duration, { type: 'read' });

    check(res, {
      'rejects unsigned request': (r) => r.status === 401 || r.status === 403,
      'does not accept unsigned request': (r) => r.status !== 200,
    });

    readErrors.add(!(res.status === 401 || res.status === 403));
  });
}

// ─── Main VU loop ───────────────────────────────────────────────────────
export default function () {
  readFlow();
  sleep(0.3);

  writeFlow();
  sleep(0.3);

  webhookFlow();
  sleep(0.5);
}

// ─── Reporting ──────────────────────────────────────────────────────────
export function handleSummary(data) {
  return {
    'tests/load/results/smoke-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data),
  };
}

function textSummary(data) {
  const p95Read = data.metrics['read_duration_ms{type:read}']?.values?.['p(95)'] ?? 0;
  const p95Write = data.metrics['write_duration_ms{type:write}']?.values?.['p(95)'] ?? 0;
  const errRate = data.metrics.http_req_failed?.values?.rate ?? 0;

  return `
─────────────────────────────────────────────
Tier 2 load smoke — summary
─────────────────────────────────────────────
  p95 read:    ${p95Read.toFixed(0)}ms   (target <500ms)
  p95 write:   ${p95Write.toFixed(0)}ms   (target <1000ms)
  Error rate:  ${(errRate * 100).toFixed(3)}%   (target <0.5%)

Verdict: ${
    p95Read < 500 && p95Write < 1000 && errRate < 0.005
      ? '✅ SHIP — all Tier 2 gates met'
      : '❌ BLOCK — one or more Tier 2 gates missed'
  }
─────────────────────────────────────────────
`;
}
