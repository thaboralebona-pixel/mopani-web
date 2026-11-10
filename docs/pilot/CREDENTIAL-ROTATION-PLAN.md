# Credential rotation plan (Phase 4, P4)

**No secret values are recorded in this document, and nothing has been rotated.** The owner carries out or supervises rotation through the Supabase dashboard and the relevant secret stores.

## 1. Inventory (names and locations only)

| Credential                   | Where it is used                                                                                                                     | Evidence                                                                                                            | Who else uses it (to confirm)                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Production database password | Direct Postgres connections (pooler or direct connection string)                                                                     | Repository search: no database connection string in code. Supabase REST uses anon key, not this password            | Any tool, script or CI job that connects directly with Postgres. Owner to list                               |
| Staging webhook secret       | `dispatch-notification` Edge Function requires header `x-webhook-secret`                                                             | Function behaviour (v7 on staging). Secret name and caller not in repository                                        | The caller that posts to the function (database trigger, pg_net, or other). **Owner to identify the caller** |
| Anon (publishable) key       | Web app client, `src/config/environment.ts` (guard accepts anon key only). `dev-setup/config.example.js` contains a placeholder name | Repository search                                                                                                   | Public by design. Not a secret. Rotation not required for this incident                                      |
| Service-role key             | Admin scripts, Edge Functions if they use it                                                                                         | Not found in repository. Edge Function `dispatch-notification` uses `verify_jwt: false` and a shared secret instead | **Owner to confirm whether any service-role key was pasted into chat or stored outside the secret manager**  |
| Resend API key               | Email delivery from Edge Function (SMTP for auth is not yet configured)                                                              | Earlier session: Resend domain and key list tools used; key values not recorded                                     | Edge Function secrets; any SMTP settings. **Owner to rotate after confirming consumers**                     |
| Paystack keys                | Not yet integrated (payments off)                                                                                                    | Not present                                                                                                         | None until payments are enabled                                                                              |
| GitHub access                | Repository push and PR; 2FA not enabled                                                                                              | Owner note                                                                                                          | Local clones, CI (no workflows in repository)                                                                |

Repository CI: no `.github/workflows` directory exists, so no CI configuration needs changing. Application configuration: `src/config/environment.ts` takes the URL and anon key at build time; neither is a secret.

## 2. Safe rotation sequence

Rotate in this order. Each step has a verification before the next.

1. **Prepare (no change):** list every consumer of the staging webhook secret and the production database password. Record each consumer's owner and where its value is stored. Do not copy values into chat or documents.
2. **Staging webhook secret first (lowest blast radius):**
   a. Generate a new secret in the secret manager (owner action).
   b. Set the new value on the Edge Function as a second accepted value **only if the function supports two values** (it currently accepts one; so this step needs a function change, which is not approved). Without that, go to c.
   c. Update the caller to the new value and the function's stored secret to the same new value in one window.
   d. Verify: send one test notification on staging and confirm delivery; confirm an old-value request is rejected.
   e. Record the time. Anything queued during the window must be re-sent (check the notifications queue for `pending` rows older than the window).
3. **Production database password last:**
   a. Confirm no consumer is still on the old password (connection list from the database, read-only).
   b. Update each consumer's stored value first, in the order: scheduled jobs, edge tools, local tools, dashboards.
   c. Rotate the password in the Supabase dashboard.
   d. Verify: each consumer reconnects; the web app (anon key, PostgREST) still works (it does not use the database password); `quote_order` returns a quote.
4. **Resend key:** create the new key, update the Edge Function secret, send a test email, then revoke the old key.
5. **Close:** record rotation dates, consumers updated, verification results. Owner signs off.

## 3. What breaks if the order is wrong

| Wrong order                                              | Result                                                                                                                                                             |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Rotate the production password before updating consumers | Every direct connection fails at once. Any job or tool using the password stops. Not visible to buyers, but orders can stop being processed if backend jobs use it |
| Change the function's webhook secret before the caller   | Every notification is rejected. Notifications queue and may be lost if they expire                                                                                 |
| Change the caller before the function                    | Same as above, in reverse                                                                                                                                          |
| Revoke the old Resend key before updating the function   | Email stops. Sign-in emails fail once SMTP is enabled                                                                                                              |
| Rotate the anon key                                      | Web app breaks until redeployed with the new key. Not required for this incident                                                                                   |

## 4. Verification after each rotation

- Staging webhook: one test notification delivered; a request with the old secret rejected.
- Production database: one connection from each consumer; `quote_order` returns a quote on the web app (staging first).
- Resend: one test email delivered; old key returns an authentication error.

## 5. Open questions for the owner

- Who or what posts to `dispatch-notification`? (The caller is not in this repository.)
- Is any service-role key stored outside the secret manager?
- Are there any direct database connections from outside Supabase (for example a reporting tool)?
