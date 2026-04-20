import type { FlagValue } from './types';

const NOT_WIRED =
  'Flags seam not yet wired. See src/server/flags/CLAUDE.md for wiring instructions.';

export async function isEnabled(_flagName: string, _defaultValue?: boolean): Promise<boolean> {
  throw new Error(NOT_WIRED);
}

export async function getValue<T extends FlagValue>(
  _flagName: string,
  _defaultValue: T,
): Promise<T> {
  throw new Error(NOT_WIRED);
}
