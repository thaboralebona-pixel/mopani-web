import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { AppConfig } from '../config/environment';

/** Creates the typed client from a validated config. Only the anon key is ever passed in. No network call is made here. */
export function createAppClient(config: AppConfig): SupabaseClient {
  return createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
  });
}
