---
name: operation-template
description: Use when creating any new data-access operation. Provides the canonical 7-step skeleton (validate input → check business rules → mutate in transaction → audit_log write → return entity) with file-location conventions.
---

# Data-Access Operation Template

Use this template when creating any new operation in your data-access
layer (e.g. `packages/database/operations/src/`).

## File Location Pattern

```
packages/database/operations/src/{domain}/{operationName}.ts
```

Examples:

- `src/auth/signUp.ts`
- `src/offers/redeemOffer.ts`
- `src/fundraising/processDonation.ts`

## Complete Template

```typescript
import { createClient } from '@supabase/supabase-js';
// TODO: update this path to your generated types file.
import type { Database } from '../../../shared/types/src/database';

// ─── Types ───────────────────────────────────────────────────

export interface {OperationName}Input {
  // Define all inputs here
  userId: string;
  // ... other inputs
}

export interface {OperationName}Result {
  // Define the returned entity
  id: string;
  // ... other fields
}

export class OperationError extends Error {
  constructor(
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'OperationError';
  }
}

export class PermissionError extends OperationError {
  constructor(message = 'Permission denied') {
    super('PERMISSION_DENIED', message);
    this.name = 'PermissionError';
  }
}

export class ValidationError extends OperationError {
  constructor(message: string, details?: unknown) {
    super('VALIDATION_ERROR', message, details);
    this.name = 'ValidationError';
  }
}

export class BusinessRuleError extends OperationError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'BusinessRuleError';
  }
}

// ─── Operation ───────────────────────────────────────────────

export async function {operationName}(
  supabase: ReturnType<typeof createClient<Database>>,
  input: {OperationName}Input,
): Promise<{OperationName}Result> {
  // 1. Validate input
  if (!input.userId) {
    throw new ValidationError('userId is required');
  }

  // 2. Check business rules
  // e.g. check eligibility, limits, status

  // 3. Perform mutation
  const { data, error } = await supabase
    .from('table_name')
    .insert({ /* ... */ })
    .select()
    .single();

  if (error) {
    throw new OperationError('DB_ERROR', error.message, error);
  }

  // 4. Write to audit_log (REQUIRED — never skip)
  await supabase.from('audit_log').insert({
    entity_type: 'table_name',
    entity_id: data.id,
    action: 'create',
    actor_user_id: input.userId,
    actor_type: 'user',
    tenant_id: data.tenant_id,
  });

  // 5. Return result
  return data as {OperationName}Result;
}
```

## Rules

- Never skip step 4 (audit_log write).
- Never throw raw Postgres errors — always wrap.
- Always return the resulting entity.
- Always write a test file in `__tests__/`.
