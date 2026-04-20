export type AuthUser = {
  id: string;
  email: string;
  firstName: string | null;
  lastName: string | null;
  imageUrl: string | null;
  role: 'admin' | 'member';
  createdAt: Date;
};

export type AuthSession = {
  userId: string;
  sessionId: string;
  orgId: string | null;
  role: 'admin' | 'member';
};

export interface AuthService {
  getCurrentUser(): Promise<AuthUser | null>;
  getCurrentSession(): Promise<AuthSession | null>;
  requireSession(): Promise<AuthSession>;
  requireRole(role: AuthUser['role']): Promise<AuthSession>;
}
