const NOT_WIRED =
  'Database seam not yet wired. See src/server/db/CLAUDE.md for wiring instructions.';

/** Placeholder for the Drizzle instance type. Replaced when the DB is wired in Phase 6. */
export type Database = unknown;

export function getDb(): Database {
  throw new Error(NOT_WIRED);
}
