---
name: run-qa
description: Use when executing test cases from the project's test registry. Explains registry columns, result CSV format, and the quick-command palette (baseline / domain / coverage).
---

# Run QA Skill

How to execute test cases from the test registry.

## Quick Commands

Run baseline (always run this first):

```bash
npm run test:rls
```

Run all tests:

```bash
npm run test
```

Run specific domain:

```bash
npx vitest run --reporter=verbose \
  packages/database/operations/__tests__/auth.test.ts
```

Run with coverage:

```bash
npm run test:coverage
```

## Reading the Test Registry

`docs/tests/test-registry.csv` columns:

```
id, domain, feature, scenario, actor_type, preconditions,
expected_output, business_rule_ref, test_runner, priority,
status, last_run, last_result
```

Filter by:

- **domain** — auth / users / billing / etc.
- **priority** — critical (run first), high, medium.
- **status** — pending, passing, failing, skip.

## Writing Results to test-results.csv

After running tests, append one row per execution:

```
run_id, timestamp, test_id, domain, scenario, actor_type, result,
actual_output, error_message, duration_ms, run_by, notes
```

`result` values: `pass`, `fail`, `skip`, `error`.

## What To Check After Any Feature Build

1. Baseline test suite must stay green.
2. Run tests for the domain you just built.
3. Check `docs/violations.md` for open issues.
4. Check `docs/completion-log.md` for failed claims.
