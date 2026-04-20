# src/server/observability/ — Observability Seam Conventions (Sentry)

This directory is the error tracking and performance monitoring vendor seam. It isolates all observability behind a stable interface. The default vendor is Sentry, wired in Phase 6.

## Purpose

- Capture and report errors with structured context.
- Track performance via spans and transactions.
- Set user context for error attribution.
- Integrate with the root error boundary for automatic error capture.

## Interface Contract

See `types.ts` for the canonical type definitions:

- `ErrorContext` — Context attached to captured errors. Fields: `userId` (optional), `extra` (optional), `tags` (optional), `level` (optional: `'fatal' | 'error' | 'warning' | 'info'`).
- `SpanContext` — Configuration for a performance span. Fields: `name`, `op` (optional), `attributes` (optional).
- `ObservabilityService` — The seam interface with methods:
  - `captureError(error, context?)` — Capture an error with optional context.
  - `startSpan<T>(context, callback)` — Run a callback within a performance span.
  - `setUser(user)` — Set or clear the user context for subsequent error reports.

## How to Capture an Error

Always use `captureError()` from the seam. Never call `Sentry.captureException` directly.

```typescript
import { captureError } from '@/server/observability';

try {
  await riskyOperation();
} catch (error) {
  captureError(error, {
    tags: { operation: 'riskyOperation' },
    extra: { inputId: id },
  });
}
```

For expected errors that are handled gracefully, use the `'warning'` or `'info'` level:

```typescript
captureError(error, { level: 'warning', tags: { context: 'user-input' } });
```

## How to Create a Performance Span

Use `startSpan()` to wrap operations you want to measure:

```typescript
import { startSpan } from '@/server/observability';

const result = await startSpan({ name: 'fetchUserProjects', op: 'db.query' }, async () => {
  return await getUserProjects(userId);
});
```

Spans nest automatically — a span created inside another span's callback becomes a child span.

## Error Boundary Integration

The root error boundary (`src/app/error.tsx`) calls `captureError()` to report unhandled errors. Every route-level `error.tsx` must also call `captureError()`:

```typescript
'use client';

import { useEffect } from 'react';
import { captureError } from '@/server/observability';

export default function ErrorBoundary({ error, reset }: { error: Error; reset: () => void }) {
  useEffect(() => {
    captureError(error);
  }, [error]);

  return (
    <div>
      <h2>Something went wrong</h2>
      <button onClick={reset}>Try again</button>
    </div>
  );
}
```

## Source Maps

When Sentry is wired, source maps are uploaded to Sentry during the CI build step. This is configured in `next.config.ts` via the Sentry webpack plugin. Source maps are not served to the client — they are uploaded to Sentry only for error deobfuscation.

## Containment Rules

- No Sentry types (`@sentry/nextjs`, `@sentry/types`) leak outside this directory.
- Application code calls `captureError()` and `startSpan()` from `@/server/observability`, never Sentry SDK methods directly.
- **Linter gate**: `@sentry/nextjs` imports outside `src/server/observability/` are build-breaking errors.

## Files

- `types.ts` — Interface contract (ErrorContext, SpanContext, ObservabilityService).
- `index.ts` — Implementation. Stub until Sentry is wired; then wraps Sentry SDK.
