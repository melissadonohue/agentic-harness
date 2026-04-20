# src/server/analytics/ — Analytics Seam Conventions (PostHog)

This directory is the product analytics vendor seam. It isolates all event tracking behind a typed interface. The default vendor is PostHog, wired in Phase 6.

## Purpose

- Track typed product analytics events.
- Identify users for analytics attribution.
- Track page views.
- Maintain a typed event catalog — events are a TypeScript union, not a bag of strings.

## Interface Contract

See `types.ts` for the canonical type definitions:

- `AnalyticsEvent` — Represents a trackable event. Fields: `name`, `properties` (optional), `userId` (optional), `timestamp` (optional).
- `AnalyticsService` — The seam interface with methods:
  - `track(event)` — Track a named event with typed properties.
  - `identify(userId, traits?)` — Associate a user with subsequent events.
  - `page(name, properties?)` — Track a page view.

## Event Catalog

Events are defined as a typed catalog, not arbitrary strings. When the seam is wired, the `AnalyticsEvent['name']` type should be narrowed to a union of known event names.

### How to Add an Event

1. **Define the event shape** in `types.ts`: Add the event name to the event name union type and define its properties schema using Zod.

```typescript
// In types.ts — example of a typed event catalog
export type AnalyticsEventName =
  | 'user.signed_up'
  | 'user.invited_teammate'
  | 'project.created'
  | 'project.deleted';

export const projectCreatedSchema = z.object({
  projectId: z.string().uuid(),
  projectName: z.string(),
});
```

2. **Add a typed helper function** that wraps `track()` with the correct event name and validated properties:

```typescript
// In index.ts
export function trackProjectCreated(props: z.infer<typeof projectCreatedSchema>) {
  track({ name: 'project.created', properties: props });
}
```

3. **Wire the trigger** in the relevant feature code. Import the typed helper from `@/server/analytics` and call it at the appropriate point (after a successful mutation, on page load, etc.).
4. **Verify** via PostHog dashboard (production) or structured log output (development/test) that the event fires with correct properties.

## How to Track a Page View

Use the `page()` method from the seam in layouts or pages:

```typescript
import { page } from '@/server/analytics';

// In a layout or page
page('Dashboard', { section: 'overview' });
```

## Containment Rules

- No PostHog types (`posthog-js`, `posthog-node`) leak outside this directory and `src/server/flags/`.
- The rest of the application imports from `@/server/analytics`, never from the PostHog SDK directly.
- **Linter gate**: `posthog-js` and `posthog-node` imports outside `src/server/analytics/` and `src/server/flags/` are build-breaking errors.

## Files

- `types.ts` — Interface contract (AnalyticsEvent, AnalyticsService, event catalog types).
- `index.ts` — Implementation. Stub until PostHog is wired; then wraps PostHog SDK.
