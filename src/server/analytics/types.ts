export type AnalyticsEvent = {
  name: string;
  properties?: Record<string, unknown>;
  userId?: string;
  timestamp?: Date;
};

export interface AnalyticsService {
  track(event: AnalyticsEvent): void;
  identify(userId: string, traits?: Record<string, unknown>): void;
  page(name: string, properties?: Record<string, unknown>): void;
}
