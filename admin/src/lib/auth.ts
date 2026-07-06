'use client';

/**
 * Admin authentication for Companion Ranchi.
 *
 * Login hits `POST /admin/auth/login` ({ email, password }) → admin JWT, which is stored
 * via the api token helpers (cookie + localStorage). `useAuthGuard` protects dashboard pages.
 */

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { apiFetch, clearToken, getToken, setToken } from './api';

/** Mirrors `admin_users` projected for the panel (see DATA_MODEL.md → admin_users). */
export type AdminRole = 'SUPER_ADMIN' | 'ADMIN' | 'SUPPORT' | 'FINANCE';

export interface AdminUser {
  id: string;
  email: string;
  name: string;
  role: AdminRole;
  permissions: string[];
  isActive: boolean;
  lastLoginAt?: string | null;
}

interface LoginResponse {
  token: string;
  admin: AdminUser;
}

/**
 * Authenticate an admin. On success the JWT is persisted and the admin profile returned.
 * Throws ApiError (e.g. UNAUTHORIZED) on failure for the caller to surface.
 */
export async function login(email: string, password: string): Promise<AdminUser> {
  const res = await apiFetch<LoginResponse>('/auth/login', {
    method: 'POST',
    skipAuth: true,
    body: { email, password },
  });

  if (!res?.token) {
    throw new Error('Login response did not include a token.');
  }
  setToken(res.token);
  return res.admin;
}

/** Fetch the currently authenticated admin (`GET /admin/auth/me`). */
export async function fetchMe(): Promise<AdminUser> {
  return apiFetch<AdminUser>('/auth/me');
}

/** Clear the session and (optionally) tell the backend to invalidate. */
export function logout(): void {
  clearToken();
}

/** Whether a token is present in the browser. */
export function isAuthenticated(): boolean {
  return Boolean(getToken());
}

export interface AuthGuardState {
  admin: AdminUser | null;
  loading: boolean;
}

/**
 * Client hook that guards a route: if no valid session, redirects to /login.
 * Returns the resolved admin + a loading flag for skeleton rendering.
 */
export function useAuthGuard(): AuthGuardState {
  const router = useRouter();
  const [admin, setAdmin] = useState<AdminUser | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    if (!getToken()) {
      router.replace('/login');
      return;
    }

    fetchMe()
      .then((me) => {
        if (active) {
          setAdmin(me);
          setLoading(false);
        }
      })
      .catch(() => {
        if (!active) return;
        clearToken();
        router.replace('/login');
      });

    return () => {
      active = false;
    };
    // router is stable across renders in the app router
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { admin, loading };
}
