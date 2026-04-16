---
name: rls-test-pattern
description: Use when writing RLS tests. Provides the four-client pattern (anon / consumer / business / staff) and shows the canonical shape for "anon is blocked", "consumer sees only own", "business sees only company", "staff sees all" tests.
---

# RLS Test Pattern

How to test RLS using four test clients.

## Setup

Clients live in your vitest setup file, typically
`packages/database/operations/vitest.setup.ts`:

- `anonClient` — unauthenticated
- `consumerClient` — authenticated consumer
- `businessClient` — authenticated business owner
- `staffClient` — authenticated staff

## Pattern For Each Actor

### Testing anon access is blocked

```typescript
it("anon cannot read sensitive_table", async () => {
  const { data } = await anonClient
    .from("sensitive_table")
    .select("id")
    .limit(1);
  expect(data).toEqual([]);
});
```

### Testing consumer sees only own data

```typescript
it("consumer sees only own rows", async () => {
  const {
    data: { user },
  } = await consumerClient.auth.getUser();
  if (!user) return; // skip if not authenticated
  const { data } = await consumerClient
    .from("table_name")
    .select("id, user_id")
    .limit(10);
  // All returned rows should belong to this user
  data?.forEach((row) => {
    expect(row.user_id).toBe(/* user's id */);
  });
});
```

### Testing business sees only company data

```typescript
it("business sees only own company rows", async () => {
  const {
    data: { user },
  } = await businessClient.auth.getUser();
  if (!user) return;
  const { data } = await businessClient
    .from("table_name")
    .select("id, company_id")
    .limit(10);
  expect(data?.length ?? 0).toBeGreaterThan(0);
  // All rows should have the same company_id
});
```

### Testing staff sees all data

```typescript
it("staff can read all rows", async () => {
  const {
    data: { user },
  } = await staffClient.auth.getUser();
  if (!user) return;
  const { error } = await staffClient
    .from("table_name")
    .select("id")
    .limit(100);
  expect(error).toBeNull();
});
```

## Running Tests

```bash
npm run test:rls    # RLS baseline only
npm run test        # all tests
npx vitest run packages/database/operations/__tests__/specific.test.ts
```

## References

- `docs/tests/test-registry.csv`
- `docs/gotchas.md#testing`
