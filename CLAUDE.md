# Agentic Harness — Agent Operating Manual

This is the root operating manual for the Agentic Harness. It is a table of contents, not an encyclopedia. Scoped rules live in subdirectory CLAUDE.md files.

## Project Purpose

A reusable scaffolding system for building products with unsupervised AI agents. Agents pick up GitHub Issues, execute them in isolation, produce PRs, review each other's work, and ship. Humans review at the PR level only. See `docs/charter.md` for the normative reference.

## Stack Baseline

Next.js (App Router) · React · shadcn/ui · Tailwind · Drizzle · Zod · Clerk · Sentry · PostHog · Vitest · Playwright · Docker. The stack is locked. Deviations require an ADR in `docs/decisions/` before any code is written. See `docs/charter.md#2-stack-baseline` for rationale.

## Global Conventions

### Naming

- Files: `kebab-case` for all files and directories.
- Components: `PascalCase` for React component files (exception to kebab-case, matches Next.js convention).
- Variables and functions: `camelCase`.
- Types and interfaces: `PascalCase`.
- Constants: `UPPER_SNAKE_CASE`.
- Database tables: `snake_case`.

### Import Ordering

1. Node built-ins (`node:fs`, `node:path`)
2. External dependencies (`react`, `next`, `zod`)
3. Internal aliases (`@/server/`, `@/lib/`, `@/components/`)
4. Relative imports (`./`, `../`)

Blank line between each group. Enforced by ESLint.

### Error Handling

Expected errors (validation failures, not-found, permission denied) return typed Result objects. Unexpected errors (database connection failures, unhandled edge cases) throw and are caught by the error boundary and Sentry.

### Vendor Seams (Non-Negotiable)

Every third-party integration is confined to a canonical module with a stable internal interface. The rest of the application imports the interface, never the vendor SDK. A custom ESLint rule per seam enforces this boundary — importing a vendor SDK outside its seam directory is a build-breaking error.

Day-one seams:

- `src/server/auth/` — Authentication (Clerk)
- `src/server/analytics/` — Product analytics (PostHog)
- `src/server/observability/` — Error tracking (Sentry)
- `src/server/flags/` — Feature flags (PostHog)
- `src/server/db/` — Database (Drizzle + Postgres)
- `src/lib/logger.ts` — Structured logging (cross-cutting)

See `docs/charter.md#3-vendor-seams` for the full seam contract.

### Commit Messages

Conventional Commits format enforced by commitlint: `type(scope): description`. Types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `test`, `ci`, `perf`, `build`.

### Testing

- Unit tests: Vitest, colocated in `tests/unit/`.
- Integration tests: Vitest with real DB, in `tests/integration/`.
- E2E tests: Playwright + axe-core, in `tests/e2e/`.
- Fixtures: `tests/fixtures/`. Seeds: `tests/seeds/`.
- MSW for network mocking in tests only — never in production code.

### Pre-commit Checks

Prettier → ESLint → gitleaks → commitlint. All must pass before a commit is accepted.

### Pre-push Checks

Type-check (`tsc --noEmit`) → Unit tests (`vitest run`). All must pass before a push is accepted.

## Subdirectory Convention Docs

Infrastructure directories (Phase 1):

- [`docs/CLAUDE.md`](docs/CLAUDE.md) — Documentation conventions, ADR format
- [`scripts/CLAUDE.md`](scripts/CLAUDE.md) — Script conventions, dispatch and bootstrap orchestration
- [`eslint-rules/CLAUDE.md`](eslint-rules/CLAUDE.md) — Custom linter rule conventions, seam enforcement

Application directories (Phase 2):

- [`src/app/CLAUDE.md`](src/app/CLAUDE.md) — Page conventions, route placement, SEO, loading/error states
- [`src/server/CLAUDE.md`](src/server/CLAUDE.md) — Server module conventions, seam interface contracts
- [`src/server/auth/CLAUDE.md`](src/server/auth/CLAUDE.md) — Auth seam conventions (Clerk)
- [`src/server/analytics/CLAUDE.md`](src/server/analytics/CLAUDE.md) — Analytics seam conventions (PostHog)
- [`src/server/observability/CLAUDE.md`](src/server/observability/CLAUDE.md) — Observability seam conventions (Sentry)
- [`src/server/flags/CLAUDE.md`](src/server/flags/CLAUDE.md) — Feature flags seam conventions (PostHog)
- [`src/server/db/CLAUDE.md`](src/server/db/CLAUDE.md) — Database conventions (Drizzle), entity patterns
- [`src/lib/CLAUDE.md`](src/lib/CLAUDE.md) — Shared utilities, logger interface
- [`src/components/CLAUDE.md`](src/components/CLAUDE.md) — Component conventions (shadcn/ui, custom)
- [`tests/CLAUDE.md`](tests/CLAUDE.md) — Test conventions, fixtures, seeds
- [`docker/CLAUDE.md`](docker/CLAUDE.md) — Docker Compose, dev environment, Mailpit

## Key References

- **Charter**: `docs/charter.md` — What the harness is and what must remain true.
- **Implementation Plan**: `docs/implementation_plan.md` — How to build the harness, phase by phase.
- **ADRs**: `docs/decisions/` — Architecture Decision Records for all deviations.
- **Quality Score**: `docs/quality-score.md` — Auto-generated quality dashboard (post-Phase 7).
- **Harness Metrics**: `docs/generated/harness-metrics.md` — Auto-generated pipeline health (post-Phase 7).
