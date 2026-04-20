import type { ErrorContext, SpanContext } from './types';

const NOT_WIRED =
  'Observability seam not yet wired. See src/server/observability/CLAUDE.md for wiring instructions.';

export function captureError(_error: unknown, _context?: ErrorContext): void {
  throw new Error(NOT_WIRED);
}

export function startSpan<T>(_context: SpanContext, _callback: () => T): T {
  throw new Error(NOT_WIRED);
}

export function setUser(_user: { id: string; email?: string } | null): void {
  throw new Error(NOT_WIRED);
}
