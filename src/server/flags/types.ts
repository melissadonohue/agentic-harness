export type FlagValue = boolean | string | number;

export interface FlagsService {
  isEnabled(flagName: string, defaultValue?: boolean): Promise<boolean>;
  getValue<T extends FlagValue>(flagName: string, defaultValue: T): Promise<T>;
}
