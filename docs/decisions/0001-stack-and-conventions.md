# 0001. Stack and Conventions

**Date**: 2026-04-20
**Status**: Accepted

## Context

The Agentic Harness needs a locked stack baseline that agents can reason about deterministically. The stack must be agent-legible (file-system routing, atomic styling, copy-paste-friendly components), type-safe end-to-end, and production-ready. Every choice needs to be a good default behind a seam, so it can be swapped later if needed.

The harness also needs strong mechanical enforcement — linters, hooks, CI gates — because unsupervised agents cannot rely on code review culture or tribal knowledge. Every invariant that matters must be enforced by a tool.

## Decision

### Stack

- **Framework**: Next.js with App Router — file-system routing is deterministic and agent-navigable.
- **UI**: React + shadcn/ui + Tailwind + next-themes — shadcn components are copy-paste-friendly (no opaque node_modules), Tailwind is atomic and greppable.
- **Validation**: Zod at every boundary — single source of truth for data shapes.
- **ORM**: Drizzle — SQL-forward design that agents can reason about without abstraction-layer guessing.
- **Environment**: @t3-oss/env-nextjs for typed environment variables.
- **Server state**: TanStack Query — explicit cache model, predictable behavior.
- **Forms**: react-hook-form with zodResolver — typed form handling with Zod integration.
- **Auth**: Clerk — session management, roles, organizations, webhooks. Contained in `src/server/auth/`.
- **Observability**: Sentry — error tracking and performance. Contained in `src/server/observability/`.
- **Analytics**: PostHog — product analytics and feature flags. Contained in `src/server/analytics/` and `src/server/flags/`.
- **Testing**: Vitest (unit/integration), Playwright + axe-core (e2e + accessibility), MSW (network mocking), Faker (synthetic data).
- **Notifications**: Sonner (toasts), shadcn Dialog (modals).
- **Dev environment**: Docker Compose with Postgres and Mailpit.
- **Deployment**: Vercel with preview environments per branch.
- **Dependencies**: Renovate with auto-merge for patches.

### Conventions

- **Monorepo vs single package**: Single package. Monorepo tooling adds navigation overhead for agents without team-scale benefits.
- **ESLint config**: Legacy `.eslintrc.cjs`. Flat config tooling support is not yet reliable enough for custom rule integration.
- **Project management**: GitHub Projects. Everything in one place — no external tools that create synchronization problems.
- **Branching**: Trunk-based with short-lived feature branches. Branch naming: `issue-<number>/<short-description>`.
- **Error handling**: Result types for expected errors, thrown exceptions for unexpected errors.
- **API routes**: Route Handlers with Zod validation on every input.
- **Commit messages**: Conventional Commits enforced by commitlint.
- **Vendor seams**: Non-negotiable. Every third-party SDK confined to its canonical module with ESLint enforcement.

## Consequences

**Positive**: Agents can navigate the codebase deterministically. Vendor lock-in is bounded by seams. Type safety is end-to-end. Mechanical enforcement prevents convention drift without human supervision.

**Negative**: The locked stack is opinionated — teams with strong preferences for other tools (Prisma over Drizzle, SWR over TanStack Query) must file an ADR before deviating. The single-package constraint may need revisiting if the product grows to platform scale.

**Neutral**: The stack is mainstream and well-documented, which means agents have strong training coverage. Tooling ecosystem is mature. Migration paths exist for every choice.
