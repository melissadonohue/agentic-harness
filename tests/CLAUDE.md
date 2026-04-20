# tests/ — Test Conventions

This directory contains all tests. Tests are organized by type, not by feature. Fixtures and seeds are shared across test types.

## Directory Structure

```
tests/
  unit/            — Vitest unit tests
  integration/     — Vitest with real database
  e2e/             — Playwright + axe-core
  fixtures/        — Shared test data factories and helpers
  seeds/           — Deterministic seed data for dispatch environments
  CLAUDE.md        — This file
```

## Test Types

### unit/ — Unit Tests (Vitest)

Test individual functions, utilities, and components in isolation. No network calls, no database, no file system.

- **File naming**: `<feature>.test.ts` (e.g., `logger.test.ts`, `project-card.test.ts`).
- **Runner**: Vitest. Run with `npm run test` or `npx vitest run`.
- **Mocking**: Use Vitest's built-in `vi.mock()` for module mocking. Use MSW for HTTP request mocking.
- **What to test**: Pure functions, utility modules, component rendering, Zod schemas, data transformations.
- **What NOT to test here**: Database queries, vendor SDK behavior, multi-page user flows.

```typescript
// tests/unit/logger.test.ts
import { describe, it, expect, vi } from 'vitest';

import { createLogger } from '@/lib/logger';

describe('logger', () => {
  it('emits structured JSON to console.info', () => {
    const spy = vi.spyOn(console, 'info').mockImplementation(() => {});
    const logger = createLogger();
    logger.info('test message', { key: 'value' });

    const output = JSON.parse(spy.mock.calls[0][0] as string);
    expect(output.message).toBe('test message');
    expect(output.context.key).toBe('value');
    spy.mockRestore();
  });
});
```

### integration/ — Integration Tests (Vitest + Real DB)

Test seam implementations with actual database connections. These verify that the repo layer, migrations, and seam wiring work together.

- **File naming**: `<feature>.test.ts` (e.g., `projects-repo.test.ts`, `auth-webhook.test.ts`).
- **Runner**: Vitest with a test database. The test database is created and torn down per test suite.
- **Database**: Uses a separate test database (not the dev database). Connection via `DATABASE_URL` in the test environment.
- **What to test**: Repo layer CRUD operations, migration correctness, seam implementation behavior, webhook handlers.
- **What NOT to test here**: UI rendering, client-side behavior.

```typescript
// tests/integration/projects-repo.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';

import { createProject, getProjectById } from '@/server/db/repos/projects';

describe('projects repo', () => {
  // Setup and teardown for test database

  it('creates and retrieves a project', async () => {
    const project = await createProject({
      name: 'Test Project',
      ownerId: 'user-123',
    });

    const retrieved = await getProjectById(project.id);
    expect(retrieved).not.toBeNull();
    expect(retrieved!.name).toBe('Test Project');
  });
});
```

### e2e/ — End-to-End Tests (Playwright + axe-core)

Test user flows end-to-end in a real browser with accessibility audits.

- **File naming**: `<feature>.spec.ts` (e.g., `dashboard.spec.ts`, `auth-flow.spec.ts`).
- **Runner**: Playwright. Run with `npx playwright test`.
- **Accessibility**: Every test includes an axe-core assertion. Zero AA-level violations is required for all user-facing pages.
- **What to test**: Page loads, navigation flows, form submissions, auth flows, error states.
- **What NOT to test here**: API-only endpoints (use integration tests), internal functions (use unit tests).

```typescript
// tests/e2e/dashboard.spec.ts
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test.describe('dashboard', () => {
  test('loads and displays projects', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: /projects/i })).toBeVisible();
  });

  test('is accessible', async ({ page }) => {
    await page.goto('/dashboard');
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
});
```

## fixtures/ — Shared Test Data

Test data factories and helpers shared across all test types.

- Use factory functions that return typed test objects with sensible defaults.
- Override specific fields per test — do not create separate fixtures for every variation.
- Use Faker with a fixed seed for deterministic synthetic data.

```typescript
// tests/fixtures/projects.ts
import { faker } from '@faker-js/faker';

faker.seed(42);

export function buildProject(overrides?: Partial<Project>) {
  return {
    id: faker.string.uuid(),
    name: faker.commerce.productName(),
    description: faker.lorem.sentence(),
    ownerId: faker.string.uuid(),
    createdAt: faker.date.past(),
    updatedAt: faker.date.recent(),
    ...overrides,
  };
}
```

## seeds/ — Dispatch Environment Seeds

Deterministic seed data used by `scripts/seed.ts` to populate dispatch environments. Every dispatched agent starts with the same baseline data.

- Seeds are NOT test fixtures — they represent a realistic baseline application state.
- Seeds include: user records, role assignments, sample entities for any defined schemas.
- Seeded by `scripts/seed.ts` using Faker with a fixed seed for reproducibility.
- Seeds are applied automatically when `scripts/dispatch.sh` creates a new dispatch environment.

## MSW — Network Mocking

Use Mock Service Worker (MSW) for mocking HTTP requests in tests. MSW intercepts requests at the network level, making mocks transparent to the code under test.

**Rules**:

- MSW is for tests only. Never import MSW in production application code.
- Define handlers in `tests/fixtures/` and import them in test setup files.
- Prefer MSW over `vi.mock()` for testing code that makes HTTP requests.

## How to Add a Test

1. **Determine the test type**: Unit for isolated logic, integration for database/seam behavior, e2e for user flows.
2. **Create the test file** in the correct directory with the correct naming convention (`.test.ts` for unit/integration, `.spec.ts` for e2e).
3. **Use fixtures** for shared test data. Import from `tests/fixtures/`.
4. **Assert specific outcomes**. Tests verify behavior, not implementation details. Assert on return values, rendered output, or database state — not on internal function calls.
5. **Include accessibility assertions** in e2e tests. Every page test runs axe-core.

## Rules

- Every PR that adds a user-facing page must include an e2e test.
- Every PR that adds a utility or seam function must include a unit or integration test.
- Prefer real implementations over mocks. Only mock at system boundaries.
- Test behavior, not implementation. Assert outcomes, not internal state.
- MSW for network mocking in tests only — never in production code.
