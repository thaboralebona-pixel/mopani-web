// Environment configuration and guard. Pure logic: no DOM, no network.
// The guard refuses to run a development build against the production project.

export const ENVIRONMENTS = ['local', 'staging', 'production'] as const;
export type Environment = (typeof ENVIRONMENTS)[number];

export interface AppConfig {
  readonly env: Environment;
  readonly supabaseUrl: string;
  readonly supabaseAnonKey: string;
}

export interface RawConfig {
  env?: unknown;
  supabaseUrl?: unknown;
  supabaseAnonKey?: unknown;
  allowProductionHost?: unknown;
}

export type ConfigResult =
  | { readonly ok: true; readonly config: AppConfig }
  | { readonly ok: false; readonly errors: readonly string[] };

// Identifier of the production project (a project reference, not a secret). Used only to refuse production hosts.
export const PRODUCTION_PROJECT_REF = 'jpjjdzlhthvookllydai';

const LOCAL_HOSTS = new Set(['127.0.0.1', 'localhost']);

function base64UrlToUtf8(segment: string): string {
  const base64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  return atob(padded);
}

/** Returns the "role" claim of a JWT-shaped key, or null if the string is not a readable JWT. */
export function decodeJwtRole(token: string): string | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(base64UrlToUtf8(parts[1] ?? '')) as { role?: unknown };
    return typeof payload.role === 'string' ? payload.role : null;
  } catch {
    return null;
  }
}

export function validateConfig(raw: RawConfig): ConfigResult {
  const errors: string[] = [];

  // 1. Environment
  const env = raw.env;
  if (typeof env !== 'string' || !(ENVIRONMENTS as readonly string[]).includes(env)) {
    errors.push('env must be one of: local, staging, production.');
  }
  const environment = (ENVIRONMENTS as readonly string[]).includes(env as string)
    ? (env as Environment)
    : null;

  // 2. Production permission
  const allowProduction = raw.allowProductionHost === true;

  // 3. URL
  let url: URL | null = null;
  if (typeof raw.supabaseUrl !== 'string' || raw.supabaseUrl.trim() === '') {
    errors.push('supabaseUrl is missing.');
  } else {
    try {
      url = new URL(raw.supabaseUrl.trim());
    } catch {
      errors.push('supabaseUrl is not a valid URL.');
    }
  }
  if (url && environment) {
    const isLocalHost = LOCAL_HOSTS.has(url.hostname);
    const isProductionHost = url.hostname.includes(PRODUCTION_PROJECT_REF);
    if (environment === 'local') {
      if (!isLocalHost) errors.push('local environment must point to localhost or 127.0.0.1.');
    } else {
      if (url.protocol !== 'https:') errors.push(`${environment} environment must use https.`);
      if (isLocalHost) errors.push(`${environment} environment cannot point to localhost.`);
    }
    if (isProductionHost && !(environment === 'production' && allowProduction)) {
      errors.push('Refusing to use the production project from a non-production build.');
    }
    if (environment === 'production') {
      if (!allowProduction) errors.push('production requires allowProductionHost: true.');
      if (!isProductionHost)
        errors.push('production environment must point to the production project.');
    }
  }

  // 4. Anon key only
  if (typeof raw.supabaseAnonKey !== 'string' || raw.supabaseAnonKey.trim() === '') {
    errors.push('supabaseAnonKey is missing.');
  } else {
    const key = raw.supabaseAnonKey.trim();
    if (key.includes('PASTE')) {
      errors.push('supabaseAnonKey is still the placeholder.');
    } else {
      const role = decodeJwtRole(key);
      if (role === 'service_role') {
        errors.push('A service_role key must never be used in client code. Refused.');
      } else if (role !== 'anon') {
        errors.push('supabaseAnonKey must be the anon key.');
      }
    }
  }

  if (errors.length > 0 || !environment || !url) {
    return { ok: false, errors };
  }
  return {
    ok: true,
    config: {
      env: environment,
      supabaseUrl: url.origin,
      supabaseAnonKey: (raw.supabaseAnonKey as string).trim(),
    },
  };
}
