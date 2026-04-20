# src/server/ — Server Module Conventions

This directory contains vendor seams — each subdirectory isolates a third-party integration behind a stable internal interface. The rest of the application imports from the seam's `index.ts`, never the vendor SDK directly. This is the single most important structural decision in the harness and it is non-negotiable.

## Directory Structure

Each vendor seam follows the same structure:

```
src/server/<seam-name>/
  types.ts    — TypeScript interfaces and types for the seam contract
  index.ts    — Implementation (stub until wired, then vendor SDK wrapper)
  CLAUDE.md   — Scoped convention doc for this seam
```

## The Seam Contract

1. `types.ts` defines the seam's interface using plain TypeScript types. No vendor types are re-exported. Functions return plain objects conforming to these types.
2. `index.ts` exports functions that implement the interface. Before wiring, these are stubs that throw descriptive errors. After wiring, they wrap the vendor SDK.
3. The rest of the application imports only from the seam's `index.ts` — never from `types.ts` directly, never from the vendor SDK.
4. A custom ESLint rule (`no-vendor-outside-seam`) blocks vendor SDK imports outside the seam directory. This is a build-breaking error, not a warning.

## How to Add a New Vendor Seam

When a new third-party integration is needed (billing, email, storage, search, etc.):

1. **Create the directory**: `src/server/<seam-name>/`.
2. **Define the interface** in `types.ts`: TypeScript types and interfaces that describe what the seam does, using only plain types (no vendor types).
3. **Create the stub** in `index.ts`: Export functions matching the interface that throw `"<Seam> not yet wired. See src/server/<seam-name>/CLAUDE.md for wiring instructions."` This lets the application compile and other code reference the seam before the vendor is wired.
4. **Write the CLAUDE.md**: Document the seam's purpose, interface contract, how to wire it, how to extend it, and what linter gates apply. Follow the pattern of existing seam CLAUDE.md files.
5. **Add the ESLint mapping**: In `.eslintrc.cjs`, add the vendor package(s) and seam directory to the `no-vendor-outside-seam` rule configuration. See `eslint-rules/CLAUDE.md` for the mapping table.
6. **Update the root CLAUDE.md**: Add the new seam to the vendor seams list.

## How to Wire an Existing Seam

Wiring replaces a stub with a live vendor SDK implementation:

1. **Install the vendor SDK**: Add the package to `package.json`.
2. **Add environment variables**: Add required env vars to `src/lib/env.ts` (server schema) and `.env.example` with documented defaults or placeholder values.
3. **Implement the interface**: Replace the stub functions in `index.ts` with vendor SDK calls. The function signatures and return types must not change — the interface is stable.
4. **Translate vendor errors**: Catch vendor-specific errors and translate them to the seam's own error types. The rest of the application never sees vendor error shapes.
5. **Write integration tests**: Add tests in `tests/integration/` that verify the seam works with the real vendor (or a test/sandbox account). Mock-free where possible.
6. **Update the CLAUDE.md**: Evolve the seam's CLAUDE.md from prescriptive cold-start instructions to a pattern reference that cites the concrete implementation.
7. **Verify the linter gate**: Run `npm run lint` and confirm the vendor SDK import is only used inside the seam directory.

## Error Handling

Seam implementations follow the project's error handling convention:

- **Expected errors** (user not found, invalid token, rate limit exceeded) are returned as typed Result objects.
- **Unexpected errors** (SDK connection failure, malformed response) are thrown and caught by the error boundary / Sentry via the observability seam.
- Vendor-specific error classes are caught inside the seam and translated to plain error types. No vendor error types leak outside the seam.

## ESLint Enforcement

The `no-vendor-outside-seam` rule in `eslint-rules/` enforces vendor containment. It maps vendor packages to allowed directories:

| Vendor Package               | Allowed In                                   |
| ---------------------------- | -------------------------------------------- |
| `@clerk/nextjs`              | `src/server/auth/`                           |
| `posthog-js`, `posthog-node` | `src/server/analytics/`, `src/server/flags/` |
| `@sentry/nextjs`             | `src/server/observability/`                  |
| `drizzle-orm`, `drizzle-kit` | `src/server/db/`, `drizzle.config.ts`        |

Importing a vendor SDK outside its allowed directories is a build-breaking error. The error message includes a remediation hint pointing to the correct seam import path.

## Day-One Seams

- `auth/` — Authentication (Clerk). See `auth/CLAUDE.md`.
- `analytics/` — Product analytics (PostHog). See `analytics/CLAUDE.md`.
- `observability/` — Error tracking and performance (Sentry). See `observability/CLAUDE.md`.
- `flags/` — Feature flags (PostHog). See `flags/CLAUDE.md`.
- `db/` — Database (Drizzle + Postgres). See `db/CLAUDE.md`.

Cross-cutting seam outside this directory:

- `src/lib/logger.ts` — Structured logging. Lives in `lib/` because it is used on both server and client paths.
