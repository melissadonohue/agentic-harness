# src/server/flags/ — Feature Flags Seam Conventions (PostHog)

This directory is the feature flags vendor seam. It isolates all flag evaluation behind a typed interface. The default vendor is PostHog feature flags, wired in Phase 6.

## Purpose

- Evaluate feature flags for progressive rollout and experimentation.
- Support boolean flags (on/off) and multi-variant flags (string/number values).
- Resolve flags on the server by default; client-side evaluation is opt-in per flag.

## Interface Contract

See `types.ts` for the canonical type definitions:

- `FlagValue` — The possible flag value types: `boolean | string | number`.
- `FlagsService` — The seam interface with methods:
  - `isEnabled(flagName, defaultValue?)` — Evaluate a boolean flag. Returns `true` or `false`.
  - `getValue<T>(flagName, defaultValue)` — Evaluate a multi-variant flag. Returns the typed value.

## Server-Resolved by Default

Flags are evaluated on the server in Server Components and API routes. This avoids layout shift from client-side flag evaluation and keeps flag logic out of the client bundle.

```typescript
import { isEnabled } from '@/server/flags';

export default async function DashboardPage() {
  const showNewNav = await isEnabled('new-navigation', false);
  return showNewNav ? <NewNavigation /> : <LegacyNavigation />;
}
```

Client-side flag evaluation is opt-in per flag — only when a flag must react to real-time changes without a page reload. This is the exception, not the default.

## How to Add a Flag

1. **Declare the flag** in `types.ts`: Add the flag name and its expected type to the flag name type (once the typed catalog is established).

```typescript
// Example typed flag catalog
export type BooleanFlag = 'new-navigation' | 'dark-mode-default' | 'invite-flow-v2';

export type MultiVariantFlag = 'pricing-tier-experiment' | 'onboarding-flow';
```

2. **Add the evaluation call** in the feature code. Import `isEnabled()` or `getValue()` from `@/server/flags` and use it to gate the feature.

3. **Document the rollout plan** in `docs/decisions/` as an ADR. Include: flag name, purpose, target audience, rollout percentage schedule, and success/failure criteria for the experiment.

4. **Clean up after rollout**: When a flag reaches 100% and the experiment is concluded, remove the flag evaluation code and the flag declaration. Dead flags are technical debt.

## Flag Evaluation Patterns

### Boolean Flag (Feature Gate)

```typescript
import { isEnabled } from '@/server/flags';

const canInvite = await isEnabled('invite-flow-v2', false);
if (canInvite) {
  // Show new invite flow
}
```

### Multi-Variant Flag (Experiment)

```typescript
import { getValue } from '@/server/flags';

const pricingTier = await getValue('pricing-tier-experiment', 'control');
// pricingTier is 'control' | 'variant-a' | 'variant-b'
```

## Containment Rules

- No PostHog types (`posthog-js`, `posthog-node`) leak outside this directory and `src/server/analytics/`.
- The rest of the application imports from `@/server/flags`, never from the PostHog SDK directly.
- **Linter gate**: `posthog-js` imports outside `src/server/flags/` and `src/server/analytics/` are build-breaking errors.

## Files

- `types.ts` — Interface contract (FlagValue, FlagsService, flag name types).
- `index.ts` — Implementation. Stub until PostHog is wired; then wraps PostHog feature flags SDK.
