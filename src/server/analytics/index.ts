import type { AnalyticsEvent } from './types';

const NOT_WIRED =
  'Analytics seam not yet wired. See src/server/analytics/CLAUDE.md for wiring instructions.';

export function track(_event: AnalyticsEvent): void {
  throw new Error(NOT_WIRED);
}

export function identify(_userId: string, _traits?: Record<string, unknown>): void {
  throw new Error(NOT_WIRED);
}

export function page(_name: string, _properties?: Record<string, unknown>): void {
  throw new Error(NOT_WIRED);
}
