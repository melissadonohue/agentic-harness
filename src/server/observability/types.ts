export type ErrorContext = {
  userId?: string;
  extra?: Record<string, unknown>;
  tags?: Record<string, string>;
  level?: 'fatal' | 'error' | 'warning' | 'info';
};

export type SpanContext = {
  name: string;
  op?: string;
  attributes?: Record<string, string | number | boolean>;
};

export interface ObservabilityService {
  captureError(error: unknown, context?: ErrorContext): void;
  startSpan<T>(context: SpanContext, callback: () => T): T;
  setUser(user: { id: string; email?: string } | null): void;
}
