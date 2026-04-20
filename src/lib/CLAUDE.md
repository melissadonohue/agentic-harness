# src/lib/ — Shared Utilities

This directory contains cross-cutting utilities used by both server and client code. Everything here is framework-agnostic and vendor-agnostic. No vendor SDKs live here — only the logger (which has no external dependencies) and pure utility functions.

## Files

### logger.ts — Structured JSON Logger

The single interface for all runtime logging. Outputs structured JSON to stdout via console methods. Works on both server (Node) and client (browser) without external dependencies.

**Interface**: `Logger` with methods `info()`, `warn()`, `error()`, `debug()`, and `child()` for scoped context.

**Usage**:

```typescript
import { logger } from '@/lib/logger';

logger.info('User signed in', { userId: '123' });
logger.error('Failed to create project', new Error('DB connection failed'), { projectName: 'foo' });

// Scoped logger with persistent context
const reqLogger = logger.child({ requestId: 'abc-123' });
reqLogger.info('Processing request'); // Includes requestId in context
```

**Rules**:

- `console.log` in application code is a linter error (future rule). Use the logger.
- `debug` level is suppressed in production.
- Error-level logs accept either an `Error` object or a context record as the second argument.

### utils.ts — Tailwind Utilities

Contains `cn()` — the class name merging utility from shadcn/ui. Combines `clsx` and `tailwind-merge` to conditionally compose Tailwind classes without conflicts.

```typescript
import { cn } from '@/lib/utils';

<div className={cn('p-4 text-sm', isActive && 'bg-primary text-primary-foreground')} />
```

### env.ts — Typed Environment Variables

Uses `@t3-oss/env-nextjs` to define and validate all environment variables at build time. Split into `server` (not exposed to client) and `client` (prefixed with `NEXT_PUBLIC_`) schemas.

**How to add an environment variable**:

1. Add the Zod schema to the appropriate section (`server` or `client`) in `env.ts`.
2. Add the runtime mapping in the `runtimeEnv` object.
3. Add the variable to `.env.example` with a documented default or placeholder value.
4. If the variable is required for a vendor seam, note which seam in a comment.

```typescript
// Adding a new server env var
server: {
  DATABASE_URL: z.string().url(),
  CLERK_SECRET_KEY: z.string().min(1), // Auth seam (src/server/auth/)
},
```

**Rules**:

- Every environment variable used in the application must be defined in `env.ts`. Accessing `process.env` directly outside `env.ts` is not allowed.
- The `skipValidation` flag is only for CI/build contexts where env vars are not available.

## How to Add a Utility

1. Create a single-purpose file with a descriptive `kebab-case` name (e.g., `format-date.ts`, `slugify.ts`).
2. Export typed functions with explicit parameter and return types. No `any`.
3. Keep it pure — no side effects, no dependencies on server or client context.
4. Add a unit test in `tests/unit/` (e.g., `tests/unit/format-date.test.ts`).
5. If the utility is only useful on the server or only on the client, consider whether it belongs in `src/server/` or a component file instead.
