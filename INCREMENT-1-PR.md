# Increment 1: Foundation (pull request record)

## Branch and scope

Branch name (to create in your repository): `increment-1-foundation`.
Scope: project scaffold, exact dependency pins, environment guard (local and staging; production refused), environment banner, typed Supabase client (anon key only), service worker shell (caches the app shell only), 360 px mobile-first layout tokens, one strings file, typecheck, format check, unit tests, build.
Not changed: database, migrations, server functions, payment code, the legacy prototype at release/index.html, the team's pgTAP suites.

## Files

Added: package.json, package-lock.json, .npmrc, tsconfig.json, .prettierrc.json, .prettierignore, .gitignore, README.md, INCREMENT-1-PR.md, index.html, public/manifest.webmanifest, public/icon.svg, public/sw.js, scripts/build.mjs, src/app/main.ts, src/config/environment.ts, src/config/environment.test.ts, src/lib/banner.ts, src/lib/banner.test.ts, src/lib/supabase.ts, src/strings/en.ts, src/styles/tokens.css, dev-setup/config.example.js.
Changed: none (new repository).

## Commands run and results

| Command                       | Result                                                                                          |
| ----------------------------- | ----------------------------------------------------------------------------------------------- |
| node --version; npm --version | v22.22.2; 10.9.7                                                                                |
| npm install                   | exit 0; lockfile written                                                                        |
| npm ls --depth=0              | @supabase/supabase-js 2.118.0; esbuild 0.25.10; prettier 3.6.2; typescript 5.9.3; vitest 3.2.7  |
| npm run typecheck             | exit 0 (after removing a Buffer dependency from the test; no extra types package needed)        |
| npm run format:check          | exit 0, "All matched files use Prettier code style!"                                            |
| npm test                      | exit 0; Test Files 2 passed; Tests 25 passed                                                    |
| npm run build                 | exit 0; "build ok: dist/"; app.js 225,990 bytes minified; gzip first-load estimate 60,483 bytes |
| npm run check (all four)      | exit 0                                                                                          |
| npm audit --omit=dev          | found 0 vulnerabilities (production dependencies)                                               |
| npm audit                     | 2 moderate, both in @vitest/mocker (test runner only; see limitations)                          |

Not run (not available in this environment): Playwright end-to-end tests, Lighthouse, screenshots at 360 px, a real browser run of the service worker. These are required for the full increment and are NOT claimed as passed.

## Claims check (every user-facing sentence in this increment)

| Sentence                                                                                                            | Accurate?                                                            |
| ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| "Mopani Corridor"                                                                                                   | Yes                                                                  |
| "This is a pilot. Payments are not available yet."                                                                  | Yes (payments are switched off)                                      |
| "Sign-in codes cannot be sent yet. You can look around, but you cannot place an order."                             | Yes while SIGN_IN_ENABLED is false, which it is                      |
| "This build cannot start because its configuration file is missing. Ask the team for the correct environment file." | Yes                                                                  |
| "This build cannot start because its configuration is not valid." plus rule text                                    | Yes; rule text names the failed rule and never echoes the key or URL |
| Environment banner "ENVIRONMENT: LOCAL" or "STAGING"                                                                | Yes; hidden in production                                            |

Removed in this increment: an unused "offline use is not available" sentence (unverified claim).
Forbidden phrases searched in the build and source: "verified seller", "secured", "your money is held", "protected", "participating taxi", "youth-owned", "credited", "someone will contact you". None found.

## Secrets and data check

- Scanned dist, src and public: no payment keys, no JWT-shaped strings in the shipped code, no phone numbers, no email addresses.
- "service_role" appears only in the guard's refusal rule and its tests, never as a key.
- The production project reference appears in the bundle, because the guard uses it to refuse production hosts. It is an identifier, not a secret, but it is the production reference. If you want it out of the bundle, it can move to a build-time setting in the next increment.
- No config file is committed: public/config.js and dev-setup/config.local.js and config.staging.js are git-ignored.

## Guard behaviour (covered by 22 unit tests)

Refused: production host from local or staging (even with the flag); production without allowProductionHost === true (a string 'true' is refused); production pointed at a non-production project; local pointed at a remote host; staging over http or at localhost; unknown environment; missing URL; malformed URL; missing key; placeholder key; non-JWT key; service_role key in any environment.
Accepted: local on 127.0.0.1 with an anon key; staging on https with an anon key; production only with the flag and the production project.
Limit: the guard checks the key's role claim. It does not verify the key's signature, and it cannot tell a real anon key from a synthetic one.

## Known limitations and accepted risks

1. Two moderate npm audit findings in @vitest/mocker (versions up to 4.1.11). The fix is Vitest 4, a breaking major change, so it is deferred to a separate reviewed change. The package runs only inside the test runner and is not in the shipped bundle (verified: zero matches for "vitest" in dist/app.js).
2. tinypool is pinned to 2.1.2 by an npm override. This removes the critical finding. The override must be removed when Vitest 4 is adopted.
3. The service worker is not yet tested in a browser. The brief requires that test.
4. The first-load figure is a gzip estimate, not a measured slow-3G transfer.
5. Sign-in is not implemented in this increment. The flag is off.

## Questions for the reviewer (blocking)

1. May I take the Vitest 4 upgrade as a separate increment, now or later?
2. Keep the production reference in the bundle as a guard identifier, or move it to build-time configuration?
