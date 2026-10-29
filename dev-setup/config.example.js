// Copy to dev-setup/config.local.js (or config.staging.js), fill in the ANON key, then copy the file to public/config.js.
// public/config.js is git-ignored. The guard in src/config/environment.ts checks every value before the app starts.
// Never put a service_role key here. Never point a development build at the production project.
window.MOPANI_CONFIG = {
  env: 'local', // 'local' | 'staging' | 'production'
  supabaseUrl: 'http://127.0.0.1:54321', // local: from `supabase start`. staging: Project Settings > API
  supabaseAnonKey: 'PASTE_ANON_KEY_HERE', // the ANON key only
  allowProductionHost: false,
};
