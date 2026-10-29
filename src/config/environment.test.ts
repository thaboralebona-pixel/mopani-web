import { describe, expect, it } from 'vitest';
import { PRODUCTION_PROJECT_REF, decodeJwtRole, validateConfig } from './environment';

// Synthetic keys only. The signature segment is a dummy: the guard reads the role claim, it does not verify signatures.
function b64url(o: object): string {
  return btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function fakeKey(role: string): string {
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ role, iss: 'synthetic' })}.dummy-signature`;
}
const ANON = fakeKey('anon');
const SERVICE = fakeKey('service_role');
const LOCAL_URL = 'http://127.0.0.1:54321';
const STAGING_URL = 'https://synthetic-staging.supabase.co';
const PROD_URL = `https://${PRODUCTION_PROJECT_REF}.supabase.co`;

function expectRefused(result: ReturnType<typeof validateConfig>, fragment: string): void {
  expect(result.ok).toBe(false);
  if (!result.ok) {
    expect(result.errors.join(' | ')).toContain(fragment);
  }
}

describe('validateConfig: accepted configurations', () => {
  it('accepts a local configuration pointing at the local stack with an anon key', () => {
    const r = validateConfig({ env: 'local', supabaseUrl: LOCAL_URL, supabaseAnonKey: ANON });
    expect(r.ok).toBe(true);
    if (r.ok)
      expect(r.config).toEqual({ env: 'local', supabaseUrl: LOCAL_URL, supabaseAnonKey: ANON });
  });

  it('accepts a staging configuration on https, not production', () => {
    const r = validateConfig({ env: 'staging', supabaseUrl: STAGING_URL, supabaseAnonKey: ANON });
    expect(r.ok).toBe(true);
  });

  it('accepts production only with the explicit flag and the production project', () => {
    const r = validateConfig({
      env: 'production',
      supabaseUrl: PROD_URL,
      supabaseAnonKey: ANON,
      allowProductionHost: true,
    });
    expect(r.ok).toBe(true);
  });

  it('strips a trailing slash from the URL', () => {
    const r = validateConfig({ env: 'local', supabaseUrl: `${LOCAL_URL}/`, supabaseAnonKey: ANON });
    expect(r.ok && r.config.supabaseUrl).toBe(LOCAL_URL);
  });
});

describe('validateConfig: production guard', () => {
  it('refuses the production project from a local build', () => {
    const r = validateConfig({ env: 'local', supabaseUrl: PROD_URL, supabaseAnonKey: ANON });
    expectRefused(r, 'Refusing to use the production project');
  });

  it('refuses the production project from a staging build, even with the flag set', () => {
    const r = validateConfig({
      env: 'staging',
      supabaseUrl: PROD_URL,
      supabaseAnonKey: ANON,
      allowProductionHost: true,
    });
    expectRefused(r, 'Refusing to use the production project');
  });

  it('refuses production without the explicit flag', () => {
    const r = validateConfig({ env: 'production', supabaseUrl: PROD_URL, supabaseAnonKey: ANON });
    expectRefused(r, 'production requires allowProductionHost: true');
  });

  it('refuses production when the flag is a string rather than true', () => {
    const r = validateConfig({
      env: 'production',
      supabaseUrl: PROD_URL,
      supabaseAnonKey: ANON,
      allowProductionHost: 'true',
    });
    expectRefused(r, 'production requires allowProductionHost: true');
  });

  it('refuses a production environment that points at a different project', () => {
    const r = validateConfig({
      env: 'production',
      supabaseUrl: STAGING_URL,
      supabaseAnonKey: ANON,
      allowProductionHost: true,
    });
    expectRefused(r, 'production environment must point to the production project');
  });
});

describe('validateConfig: environment and URL rules', () => {
  it('refuses an unknown environment name', () => {
    expectRefused(
      validateConfig({ env: 'prod', supabaseUrl: STAGING_URL, supabaseAnonKey: ANON }),
      'env must be one of'
    );
  });

  it('refuses a local environment that points to a remote host', () => {
    expectRefused(
      validateConfig({ env: 'local', supabaseUrl: 'https://example.test', supabaseAnonKey: ANON }),
      'local environment must point to localhost'
    );
  });

  it('refuses staging over plain http', () => {
    expectRefused(
      validateConfig({
        env: 'staging',
        supabaseUrl: 'http://synthetic-staging.test',
        supabaseAnonKey: ANON,
      }),
      'staging environment must use https'
    );
  });

  it('refuses staging pointing at localhost', () => {
    expectRefused(
      validateConfig({ env: 'staging', supabaseUrl: 'https://localhost', supabaseAnonKey: ANON }),
      'staging environment cannot point to localhost'
    );
  });

  it('refuses a missing URL', () => {
    expectRefused(
      validateConfig({ env: 'local', supabaseAnonKey: ANON }),
      'supabaseUrl is missing'
    );
  });

  it('refuses a malformed URL', () => {
    expectRefused(
      validateConfig({ env: 'local', supabaseUrl: 'not a url', supabaseAnonKey: ANON }),
      'supabaseUrl is not a valid URL'
    );
  });
});

describe('validateConfig: key rules', () => {
  it('refuses a service_role key outright, in any environment', () => {
    for (const env of ['local', 'staging'] as const) {
      const url = env === 'local' ? LOCAL_URL : STAGING_URL;
      expectRefused(
        validateConfig({ env, supabaseUrl: url, supabaseAnonKey: SERVICE }),
        'service_role key must never be used in client code'
      );
    }
  });

  it('refuses a missing key', () => {
    expectRefused(
      validateConfig({ env: 'local', supabaseUrl: LOCAL_URL }),
      'supabaseAnonKey is missing'
    );
  });

  it('refuses the placeholder key', () => {
    expectRefused(
      validateConfig({
        env: 'local',
        supabaseUrl: LOCAL_URL,
        supabaseAnonKey: 'PASTE_ANON_KEY_HERE',
      }),
      'still the placeholder'
    );
  });

  it('refuses a key that is not a readable JWT', () => {
    expectRefused(
      validateConfig({ env: 'local', supabaseUrl: LOCAL_URL, supabaseAnonKey: 'not-a-jwt' }),
      'supabaseAnonKey must be the anon key'
    );
  });
});

describe('decodeJwtRole', () => {
  it('reads the role claim from a synthetic key', () => {
    expect(decodeJwtRole(fakeKey('anon'))).toBe('anon');
  });

  it('returns null for a malformed payload', () => {
    expect(decodeJwtRole('a.@@@.c')).toBeNull();
  });

  it('returns null when there is no role claim', () => {
    expect(decodeJwtRole(`${b64url({})}.${b64url({ sub: 'x' })}.s`)).toBeNull();
  });
});
