# src/server/auth/ — Auth Seam Conventions (Clerk)

This directory is the authentication vendor seam. It isolates all authentication, session management, and role-based access control behind a stable interface. The default vendor is Clerk, wired in Phase 6.

## Purpose

- Authenticate users and manage sessions.
- Provide role-based access control (RBAC) with typed roles.
- Handle webhook-driven lifecycle events (user created, updated, deleted).
- Sync external auth state to the application database.

## Interface Contract

See `types.ts` for the canonical type definitions:

- `AuthUser` — Represents an authenticated user. Fields: `id`, `email`, `firstName`, `lastName`, `imageUrl`, `role`, `createdAt`. All plain types, no vendor types.
- `AuthSession` — Represents an active session. Fields: `userId`, `sessionId`, `orgId`, `role`.
- `AuthService` — The seam interface with methods:
  - `getCurrentUser()` — Returns the current user or null.
  - `getCurrentSession()` — Returns the current session or null.
  - `requireSession()` — Returns the current session or throws (use in auth-guarded routes).
  - `requireRole(role)` — Returns the current session if the user has the required role, or throws.

## How to Add a Role

1. Extend the role union in `types.ts`. The current roles are `'admin' | 'member'`. Add the new role to the union type in both `AuthUser['role']` and `AuthSession['role']`.
2. Add a permission guard function if the role implies specific permissions (e.g., `requireOwner()`).
3. Update integration tests in `tests/integration/` to cover the new role.
4. If using Clerk: configure the role in the Clerk Dashboard and update the webhook handler to map the Clerk role to the seam's role type.

## How to Add a Route Guard

Use the seam's exported functions in API routes and server components:

```typescript
import { requireSession, requireRole } from '@/server/auth';

// Any authenticated user
export async function GET() {
  const session = await requireSession();
  // session.userId is available
}

// Admin only
export async function DELETE() {
  const session = await requireRole('admin');
  // Only reaches here if user is an admin
}
```

In `(auth)/` layouts, call `requireSession()` at the layout level to enforce authentication for all child routes. Redirect unauthenticated users to the sign-in page.

## Clerk Webhook Handling

When Clerk is wired, the webhook handler lives in this directory (not in `src/app/api/`). It:

1. Verifies the webhook signature using Clerk's signing secret.
2. Handles `user.created`, `user.updated`, and `user.deleted` events.
3. Syncs user data to the application database via the db seam's repo layer.
4. Returns plain objects matching the seam's own types — no Clerk types leak into the sync logic.

The webhook endpoint is registered as an API route at `src/app/api/webhooks/clerk/route.ts`, but the handler logic is imported from this directory.

## Containment Rules

- No Clerk types (`@clerk/nextjs`, `@clerk/types`) leak outside this directory.
- Functions return plain objects matching `AuthUser`, `AuthSession`, etc.
- The rest of the application imports from `@/server/auth`, never from `@clerk/nextjs`.
- **Linter gate**: `@clerk/nextjs` imports outside `src/server/auth/` are build-breaking errors. The ESLint rule `no-vendor-outside-seam` enforces this.

## Files

- `types.ts` — Interface contract (AuthUser, AuthSession, AuthService).
- `index.ts` — Implementation. Stub until Clerk is wired; then wraps Clerk SDK.
