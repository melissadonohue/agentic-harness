import type { AuthSession, AuthUser } from './types';

const NOT_WIRED = 'Auth seam not yet wired. See src/server/auth/CLAUDE.md for wiring instructions.';

export async function getCurrentUser(): Promise<AuthUser | null> {
  throw new Error(NOT_WIRED);
}

export async function getCurrentSession(): Promise<AuthSession | null> {
  throw new Error(NOT_WIRED);
}

export async function requireSession(): Promise<AuthSession> {
  throw new Error(NOT_WIRED);
}

export async function requireRole(_role: AuthUser['role']): Promise<AuthSession> {
  throw new Error(NOT_WIRED);
}
