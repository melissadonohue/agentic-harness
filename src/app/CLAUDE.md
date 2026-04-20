# src/app/ — Page Conventions

This directory contains all Next.js App Router pages, layouts, and API route handlers. Every user-facing route lives here. Every API endpoint lives here.

## Route Groups

Routes are organized into route groups. Route groups use parenthesized directory names and do not affect the URL path.

- `(auth)/` — Auth-guarded routes. Everything behind login: dashboard, settings, team management. The route group layout wraps children in the authenticated navigation shell and enforces session requirements.
- `(marketing)/` — Public marketing pages. Landing page, pricing, about, blog. The route group layout wraps children in the public navigation shell with header and footer.
- `api/` — API route handlers. RESTful endpoints consumed by the client and external integrations. Not a route group — `api/` is a real URL segment.

## How to Add a Page

1. Determine the correct route group: `(auth)/` for authenticated pages, `(marketing)/` for public pages.
2. Create the route directory matching the desired URL path. Example: `(auth)/dashboard/settings/` for `/dashboard/settings`.
3. Create `page.tsx` as a Server Component (no `'use client'` directive). Add `'use client'` only if the page itself requires interactivity — prefer pushing interactivity into child components instead.
4. Create `loading.tsx` with a skeleton or spinner for the Suspense fallback.
5. Create `error.tsx` with `'use client'` directive that calls `captureError()` from `@/server/observability` and renders a user-friendly error state.
6. Export `metadata` or `generateMetadata` for SEO (see below).
7. Add a Playwright + axe-core test in `tests/e2e/` (see below).

### File Naming Within Route Directories

- `page.tsx` — The page component. Required.
- `loading.tsx` — Suspense fallback. Required for all pages.
- `error.tsx` — Error boundary. Required for all pages. Must use `'use client'`.
- `layout.tsx` — Layout wrapper. Only when the route needs its own layout nesting.
- `not-found.tsx` — Custom 404 for this route segment. Optional.

## SEO Metadata

Every page exports static `metadata` or a `generateMetadata` function. No page ships without metadata.

Static metadata for pages with fixed content:

```typescript
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Settings | Agentic Harness',
  description: 'Manage your account settings and preferences.',
};
```

Dynamic metadata for pages with variable content:

```typescript
import type { Metadata } from 'next';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  // Fetch data needed for metadata
  return {
    title: `Project ${id} | Agentic Harness`,
  };
}
```

## Data Fetching

Server Components are the default. Data is fetched directly in the component using async/await — no `useEffect`, no client-side fetching for initial page data.

```typescript
// page.tsx — Server Component (default, no directive needed)
import { getDb } from '@/server/db';

export default async function ProjectsPage() {
  const projects = await getProjects();
  return <ProjectList projects={projects} />;
}
```

Add `'use client'` only when the component requires browser APIs, event handlers, or React hooks (useState, useEffect, etc.). When interactivity is needed, push it to the smallest possible child component — keep the page-level component as a Server Component.

Client-side data mutations use TanStack Query with API route handlers. Forms use `react-hook-form` with `zodResolver`.

## Layout Nesting

The root layout (`src/app/layout.tsx`) provides global providers: `ThemeProvider` (next-themes), `TooltipProvider` (shadcn/ui). It sets the HTML lang attribute, font, and base metadata.

Route group layouts add navigation shells:

- `(auth)/layout.tsx` — Authenticated shell: sidebar, top bar, session enforcement. Calls `requireSession()` from `@/server/auth` and redirects unauthenticated users.
- `(marketing)/layout.tsx` — Public shell: header with navigation, footer.

Do not duplicate providers across layouts. Providers live in the root layout only.

## API Route Handlers

API routes live in `api/` and use Next.js Route Handlers (exported functions named after HTTP methods).

### How to Add an API Route

1. Create the route directory: `api/<resource>/route.ts` for collection endpoints, `api/<resource>/[id]/route.ts` for item endpoints.
2. Define Zod schemas for request validation (body, query params, route params).
3. Export named functions for each HTTP method: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`.
4. Validate all inputs with Zod before processing. Return typed error responses for validation failures.
5. Use the repo layer from `@/server/db` for data access — never import Drizzle directly.

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';

const createProjectSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const body = await request.json();
  const parsed = createProjectSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  // Use repo layer for data access
  const project = await createProject(parsed.data);
  return NextResponse.json(project, { status: 201 });
}
```

### API Route Rules

- Every input is validated with Zod. No exceptions.
- Auth-guarded endpoints call `requireSession()` or `requireRole()` from `@/server/auth`.
- Error responses use consistent shape: `{ error: string | object }` with appropriate HTTP status codes.
- No direct database imports — use the repo layer from `@/server/db`.

## Testing Requirement

Every user-facing page must have at least one Playwright + axe-core test in `tests/e2e/`. The test must:

1. Navigate to the page.
2. Assert core functionality renders correctly.
3. Run axe-core and assert zero AA-level violations.

```typescript
// tests/e2e/dashboard.spec.ts
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('dashboard page loads and is accessible', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /dashboard/i })).toBeVisible();

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

When you add a page, you add its test. The PR is incomplete without both.
