---
name: error-patterns
description: Use when throwing, catching, or displaying errors from data-access operations. Defines the OperationError hierarchy (Permission, Validation, BusinessRule) and the mapping from error code → HTTP status → user-facing message.
---

# Error Patterns

How to throw, catch, and display typed errors.

## Error Types (defined in each operation file)

```typescript
// Base error
export class OperationError extends Error {
  constructor(
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = "OperationError";
  }
}

// Permission denied (RLS or permission-check function returned false)
export class PermissionError extends OperationError {
  constructor(message = "Permission denied") {
    super("PERMISSION_DENIED", message);
  }
}

// Bad input from caller
export class ValidationError extends OperationError {
  constructor(message: string, details?: unknown) {
    super("VALIDATION_ERROR", message, details);
  }
}

// Domain rule violation
export class BusinessRuleError extends OperationError {
  constructor(code: string, message: string) {
    super(code, message);
  }
}
```

## Throwing Errors

In data-access operations:

```typescript
// Never do this:
throw error; // raw Postgres error

// Always do this:
throw new OperationError("DB_ERROR", error.message, error);
throw new ValidationError("userId is required");
throw new BusinessRuleError(
  "MONTHLY_LIMIT_REACHED",
  "You have already redeemed this offer this month",
);
throw new PermissionError("You cannot access this resource");
```

## Catching in API Routes

```typescript
try {
  const result = await someOperation(supabase, input);
  res.json({ data: result });
} catch (error) {
  if (error instanceof PermissionError) {
    res.status(403).json({ error: error.message, code: error.code });
  } else if (error instanceof ValidationError) {
    res.status(400).json({ error: error.message, code: error.code });
  } else if (error instanceof BusinessRuleError) {
    res.status(422).json({ error: error.message, code: error.code });
  } else if (error instanceof OperationError) {
    res.status(500).json({ error: "Internal error", code: error.code });
  } else {
    res.status(500).json({ error: "Unexpected error" });
  }
}
```

## Displaying in UI

Never show raw error codes to users. Map to friendly messages:

```typescript
const ERROR_MESSAGES: Record<string, string> = {
  MONTHLY_LIMIT_REACHED: "You've already used this offer this month",
  NO_FUNDRAISER_CREDITS: "You need to make a donation first",
  OFFER_EXPIRED: "This offer has ended",
  PERMISSION_DENIED: "You don't have access to this",
};
```
