/**
 * Admin API client for Companion Ranchi.
 *
 * All requests target `${NEXT_PUBLIC_API_BASE_URL}/api/admin` and attach the admin JWT
 * (read from cookie or localStorage). The backend speaks the envelope defined in docs/API.md:
 *
 *   success: { "success": true, "data": {...}, "meta": {...} }
 *   error:   { "success": false, "error": { "code", "message", "details": [] } }
 */

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/+$/, '') || 'http://localhost:4000';

/** Base for every admin endpoint, e.g. `${ADMIN_API_BASE}/dashboard`. */
export const ADMIN_API_BASE = `${API_BASE_URL}/api/admin`;

export const TOKEN_KEY = 'cr_admin_token';

/** Error codes from docs/API.md. */
export type ApiErrorCode =
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'RATE_LIMITED'
  | 'PAYMENT_ERROR'
  | 'INTERNAL';

export interface ApiMeta {
  page: number;
  limit: number;
  total: number;
}

export interface ApiSuccess<T> {
  success: true;
  data: T;
  meta?: ApiMeta;
}

export interface ApiErrorBody {
  success: false;
  error: {
    code: ApiErrorCode | string;
    message: string;
    details?: unknown[];
  };
}

/** Thrown for any non-2xx response or transport failure. */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: unknown[];

  constructor(status: number, code: string, message: string, details: unknown[] = []) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

/* -------------------------------------------------------------------------- */
/* Token storage (cookie + localStorage, SSR-safe)                             */
/* -------------------------------------------------------------------------- */

const COOKIE_MAX_AGE = 60 * 60 * 24 * 7; // 7 days

function isBrowser(): boolean {
  return typeof window !== 'undefined';
}

function readCookie(name: string): string | null {
  if (!isBrowser()) return null;
  const match = document.cookie
    .split('; ')
    .find((row) => row.startsWith(`${name}=`));
  return match ? decodeURIComponent(match.split('=').slice(1).join('=')) : null;
}

export function getToken(): string | null {
  if (!isBrowser()) return null;
  return localStorage.getItem(TOKEN_KEY) ?? readCookie(TOKEN_KEY);
}

export function setToken(token: string): void {
  if (!isBrowser()) return;
  localStorage.setItem(TOKEN_KEY, token);
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  document.cookie = `${TOKEN_KEY}=${encodeURIComponent(
    token,
  )}; Path=/; Max-Age=${COOKIE_MAX_AGE}; SameSite=Lax${secure}`;
}

export function clearToken(): void {
  if (!isBrowser()) return;
  localStorage.removeItem(TOKEN_KEY);
  document.cookie = `${TOKEN_KEY}=; Path=/; Max-Age=0; SameSite=Lax`;
}

/* -------------------------------------------------------------------------- */
/* Request helpers                                                             */
/* -------------------------------------------------------------------------- */

export interface ApiFetchOptions extends Omit<RequestInit, 'body'> {
  /** JSON body — serialized automatically. For non-JSON use `rawBody`. */
  body?: unknown;
  /** Query params appended to the path. */
  params?: Record<string, string | number | boolean | undefined | null>;
  /** Skip attaching the auth token (e.g. for login). */
  skipAuth?: boolean;
}

function buildUrl(path: string, params?: ApiFetchOptions['params']): string {
  const normalized = path.startsWith('/') ? path : `/${path}`;
  const url = `${ADMIN_API_BASE}${normalized}`;
  if (!params) return url;
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === '') continue;
    search.append(key, String(value));
  }
  const qs = search.toString();
  return qs ? `${url}?${qs}` : url;
}

/**
 * Perform an authenticated admin API call and unwrap `data`.
 *
 * @example
 *   const dash = await apiFetch<DashboardStats>('/dashboard');
 *   await apiFetch('/companions/123/approve', { method: 'POST' });
 */
export async function apiFetch<T = unknown>(
  path: string,
  opts: ApiFetchOptions = {},
): Promise<T> {
  const { body, params, skipAuth, headers, ...rest } = opts;

  const finalHeaders: Record<string, string> = {
    Accept: 'application/json',
    ...(headers as Record<string, string> | undefined),
  };

  if (body !== undefined) {
    finalHeaders['Content-Type'] = 'application/json';
  }

  if (!skipAuth) {
    const token = getToken();
    if (token) finalHeaders['Authorization'] = `Bearer ${token}`;
  }

  let res: Response;
  try {
    res = await fetch(buildUrl(path, params), {
      ...rest,
      headers: finalHeaders,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      cache: 'no-store',
    });
  } catch (err) {
    throw new ApiError(0, 'NETWORK_ERROR', 'Unable to reach the server. Check your connection.');
  }

  // 204 / empty body
  if (res.status === 204) {
    return undefined as T;
  }

  let payload: unknown = null;
  const text = await res.text();
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = null;
    }
  }

  if (!res.ok) {
    // Auto-logout on auth failure so the guard can redirect.
    if (res.status === 401) clearToken();
    const errBody = payload as ApiErrorBody | null;
    const code = errBody?.error?.code ?? 'INTERNAL';
    const message =
      errBody?.error?.message ?? `Request failed (${res.status} ${res.statusText})`;
    const details = errBody?.error?.details ?? [];
    throw new ApiError(res.status, String(code), message, details);
  }

  const okBody = payload as ApiSuccess<T> | null;
  if (okBody && typeof okBody === 'object' && 'success' in okBody) {
    return okBody.data;
  }
  // Tolerate endpoints that return a bare object.
  return payload as T;
}

/**
 * Like {@link apiFetch} but also returns pagination `meta`.
 * Use for list endpoints where total/page is needed for the DataTable.
 */
export async function apiFetchList<T = unknown>(
  path: string,
  opts: ApiFetchOptions = {},
): Promise<{ data: T; meta?: ApiMeta }> {
  const { body, params, skipAuth, headers, ...rest } = opts;

  const finalHeaders: Record<string, string> = {
    Accept: 'application/json',
    ...(headers as Record<string, string> | undefined),
  };
  if (body !== undefined) finalHeaders['Content-Type'] = 'application/json';
  if (!skipAuth) {
    const token = getToken();
    if (token) finalHeaders['Authorization'] = `Bearer ${token}`;
  }

  let res: Response;
  try {
    res = await fetch(buildUrl(path, params), {
      ...rest,
      headers: finalHeaders,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      cache: 'no-store',
    });
  } catch {
    throw new ApiError(0, 'NETWORK_ERROR', 'Unable to reach the server. Check your connection.');
  }

  const text = await res.text();
  const payload = text ? (JSON.parse(text) as ApiSuccess<T> | ApiErrorBody) : null;

  if (!res.ok) {
    if (res.status === 401) clearToken();
    const errBody = payload as ApiErrorBody | null;
    throw new ApiError(
      res.status,
      String(errBody?.error?.code ?? 'INTERNAL'),
      errBody?.error?.message ?? `Request failed (${res.status})`,
      errBody?.error?.details ?? [],
    );
  }

  const okBody = payload as ApiSuccess<T>;
  return { data: okBody.data, meta: okBody.meta };
}

/**
 * SWR fetcher. Key is the admin API path (with optional querystring), e.g. `/users?page=1`.
 */
export const swrFetcher = <T>(path: string): Promise<T> => apiFetch<T>(path);
