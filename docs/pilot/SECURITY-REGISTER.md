# Security remediation register

Version: Phase 3 (10 Nov 2026). Supersedes the SEC-01 to SEC-13 table from commit `e4a5997`.

ID mapping from the old register: old SEC-02 (driver/marshal views) is now SEC-02 (unchanged). Old SEC-03 (seller_public) is now SEC-05. Old SEC-06 (request_subscription) is now SEC-04. Old SEC-07 (sa_id_is_youth) is now SEC-03. Old SEC-04/05 (production policies) are now SEC-06. Old SEC-09/10/11 are now SEC-08/09/10 and UV-04. Old SEC-12 is now SEC-11. Old SEC-13 is now SEC-12. Anyone tracking IDs from the old register should use this mapping.

Method: read-only queries against staging (`mopani-staging`) and production definitions, as recorded in each entry. Nothing in this register is marked fixed unless the change was applied and tested. Staging changes are not production changes.

Status vocabulary:

- **Confirmed**: reproduced by a read-only query or a rolled-back dry run, with the query result cited.
- **Unverified**: a concern from reading code or notes that has not been checked against the live definition.
- **Fixed (staging)**: change applied to staging and tested there. Production still exposed unless stated.
- **Production-blocking**: must be fixed or explicitly accepted in writing by the owner before any real order.

---

## Part A: Confirmed

### SEC-01 — `request_withdrawal_v2` callable by sellers while payments are off

- **Severity:** High (financial). **Confirmed.**
- **Environment:** staging and production (both show `authenticated` EXECUTE, 10 Nov).
- **Exact object:** `public.request_withdrawal_v2(numeric)`, SECURITY DEFINER. Also `public.seller_withdrawals` (authenticated has INSERT/UPDATE/DELETE grants, limited only by RLS).
- **Evidence:** grant query shows `auth_exec = true`, `anon_exec = false`. Function body: no idempotency key, no `payments_live` check, moves `available_balance` to pending and writes a debit row. Full analysis: `docs/pilot/WITHDRAWAL-CALL-CHAIN.md`.
- **Exploitation scenario:** a KYC-verified seller calls the RPC directly through the API, repeatedly, creating pending withdrawal liabilities. There is no cancel path, so the balance stays locked. A second settlement path (`approve_withdrawal` vs `mark_payout_settled`, which debit different buckets and are not linked) could settle the same money twice if an admin uses both.
- **Business impact:** creates financial liabilities for a money feature the owner has not approved. Risk of double settlement and seller disputes.
- **Recommended fix:** staging draft `docs/pilot/remediation/SEC-01-withdrawal-lockdown.sql` (revoke EXECUTE on `request_withdrawal_v2` from public, anon, authenticated; revoke write grants on `seller_withdrawals` from authenticated). Separate decision on the settlement paths.
- **Dependencies:** dependency check on `trigger_create_wallet` before any `seller_wallets` or `seller_kyc` grant change (excluded from the draft). Owner approval.
- **Verification:** dry run inside a transaction on staging, rolled back: after revoke, `auth_can_withdraw_after = false`, `auth_update_withdrawals_after = false`. Not yet applied and committed.
- **Rollback:** `grant execute on function public.request_withdrawal_v2(numeric) to authenticated;` and re-grant table privileges as they were.
- **Production-blocking:** **Yes.**
- **Status:** Confirmed. Draft only. Not fixed.

### SEC-02 — Driver and marshal public views expose personal data to any signed-in user

- **Severity:** High (privacy). **Confirmed.**
- **Environment:** staging (checked). Production not separately checked in this pass; earlier note reports the same view definitions.
- **Exact objects:** `public.public_driver_profiles`, `public.public_marshal_profiles`. Owner `postgres`, `security_invoker=false`, grants: authenticated SELECT true, anon SELECT false.
- **Evidence:** grant query above. Column review: `docs/pilot/PRIVACY-VIEWS-REVIEW.md`. Exposed: `profile_id` (auth user ID), `taxi_partner_id`, `rating`, `total_deliveries`, `active`, `vehicle_type` (driver only), `max_load_kg` (driver only).
- **Exploitation scenario:** a signed-in buyer or seller queries the views and matches `profile_id` to build a list of drivers and marshals with partner affiliation and performance rating.
- **Business impact:** privacy breach of drivers and marshals (POPIA exposure), and disclosure of taxi association membership.
- **Recommended fix:** draft `docs/pilot/remediation/SEC-02-privacy-views.sql` (revoke SELECT from authenticated and anon). Before any role needs driver or marshal names, add narrow `SECURITY DEFINER` functions returning only the agreed columns for one order.
- **Dependencies:** dependency check passed on staging (no dependent views, functions or frontend references). Re-check on production before apply.
- **Verification:** `has_table_privilege` returns false for authenticated and anon after apply; catalogue and quote still load.
- **Rollback:** `grant select on public.public_driver_profiles, public.public_marshal_profiles to authenticated;`
- **Production-blocking:** **Yes.**
- **Status:** Confirmed. Draft only.

### SEC-03 — `sa_id_is_youth` callable anonymously with an ID number

- **Severity:** High (privacy / POPIA). **Confirmed.**
- **Environment:** staging (checked). Production: not checked in this pass.
- **Exact object:** `public.sa_id_is_youth(text)`, SECURITY INVOKER, IMMUTABLE.
- **Evidence:** `anon_exec = true`, `auth_exec = true`. Body: reads six digits as a date of birth, returns a boolean for age 18–35 or NULL. No table write, no logging statement inside the function.
- **Exploitation scenario:** an anonymous caller submits an ID number (or enumerates date ranges) to learn the age band. The caller sends the full ID number over the API, so it reaches database and gateway logs (gateway logging unverified).
- **Business impact:** no pilot requirement; any use with real ID numbers is unnecessary exposure of personal information.
- **Recommended fix:** draft `docs/pilot/remediation/SEC-03-sa-id-youth-revoke.sql`. Keep the function; revoke from public, anon, authenticated. Remove only with owner approval.
- **Dependencies:** dependency search for references in functions, views, triggers and policies (to be run before apply).
- **Verification:** `has_function_privilege` false for anon and authenticated after apply.
- **Rollback:** re-grant to anon and authenticated.
- **Production-blocking:** **Yes.**
- **Status:** Confirmed. Draft only.

### SEC-04 — `request_subscription` callable by sellers

- **Severity:** Medium. **Confirmed** (grant). Side effects **unverified** beyond the insert.
- **Environment:** staging (checked). Production: not checked in this pass.
- **Exact object:** `public.request_subscription(text)`, SECURITY DEFINER, checks `auth.uid()`, writes a pending payment row.
- **Evidence:** `auth_exec = true`. Staging subscription table has 0 rows.
- **Exploitation scenario:** a seller creates subscription payment requests for a plan that is not approved.
- **Business impact:** creates pending obligations for an unapproved revenue feature.
- **Recommended fix:** draft `docs/pilot/remediation/SEC-04-subscription-revoke.sql`.
- **Dependencies:** read the full body first (unverified concern below).
- **Verification:** `has_function_privilege('authenticated', ...)` returns false after apply.
- **Rollback:** re-grant to authenticated.
- **Production-blocking:** Yes, for the pilot (legacy feature must not be live).
- **Status:** Confirmed grant exposure. Draft only.

### SEC-05 — `seller_public` readable by anonymous visitors

- **Severity:** Low–Medium. **Confirmed** (grant). Column list **unverified** in this pass.
- **Environment:** staging. Production: not checked in this pass.
- **Exact object:** `public.seller_public` (view, owner `postgres`, default invoker mode, so the view runs as owner).
- **Evidence:** `anon_select = true`, `auth_select = true`.
- **Exploitation scenario:** an anonymous caller enumerates seller identifiers and display names and districts.
- **Business impact:** limited, but it exposes seller IDs that enable linking across other data.
- **Recommended fix:** confirm the exact column list. If it contains an internal UUID, replace with a public slug. Keep the anon grant only for the columns the public catalogue needs.
- **Dependencies:** frontend does not query this view (verified: `src/` queries only `products`, `delivery_routes`, `quote_order`).
- **Verification:** column listing before and after.
- **Rollback:** restore prior definition.
- **Production-blocking:** No, unless the view exposes contact details. Owner to confirm.
- **Status:** Confirmed grant. Column content unverified.

### SEC-06 — Production `products`, `orders` and `deliveries` still use the old policies

- **Severity:** High (for buyer and seller privacy). **Confirmed** on production (policy list read 10 Nov).
- **Environment:** production exposed. Staging fixed.
- **Exact objects:** `products` (unrestricted public read), `orders` (sellers read full order rows, including buyer address), `deliveries` (exposes driver and marshal IDs and proof photos to participants).
- **Evidence:** production policy list. Staging v2 migration applied 10 Nov; role tests passed inside rolled-back transactions (anon sees only listed products; sellers read sales via `seller_sales()`; buyers read delivery status via `buyer_delivery()` without driver IDs).
- **Exploitation scenario:** an unlisted or draft product is readable by anyone. A seller reads buyer delivery addresses. A buyer learns driver and marshal identity.
- **Business impact:** buyer address disclosure to sellers; driver and marshal identity disclosure.
- **Recommended fix:** apply the staged v2 migration to production after owner approval, in the same order as tested, with the staging test script re-run afterwards.
- **Dependencies:** `seller_sales()` and `buyer_delivery()` must exist on production first (they do not, per staging comparison).
- **Verification:** repeat the role test set on production after apply (read-only checks plus rolled-back transaction).
- **Rollback:** restore the prior policies from the captured policy list.
- **Production-blocking:** **Yes.**
- **Status:** Fixed (staging). Production not fixed.

### SEC-07 — Production withdrawal and related grants unchanged

- Merged into SEC-01 (same object, same environment).

### SEC-08 — `is_admin()` callable by anonymous visitors

- **Severity:** Info. **Confirmed** (grant).
- **Evidence:** `anon_exec = true`, `auth_exec = true`.
- **Exploitation scenario:** an anonymous caller learns only whether their own (null) identity is an admin. No data exposed.
- **Recommended fix:** none required for the pilot; revoke from anon as hygiene after review of all callers.
- **Production-blocking:** No.
- **Status:** Confirmed. Low concern.

### SEC-09 — Trigger functions with anon EXECUTE

- **Severity:** Info. **Confirmed** (grant). Trigger functions cannot be called as RPCs with normal arguments.
- **Objects:** `charge_listing_fee()`, `enforce_kyc_on_withdrawal()`.
- **Recommended fix:** none; retain.
- **Production-blocking:** No.

### SEC-10 — Admin-named functions callable by signed-in users

- **Severity:** Low. **Confirmed** (grant). Bodies **confirmed** to check `is_admin()` for `admin_approve`, `admin_set_driver_fixed_fee`, `admin_set_driver_tier_fees`, `admin_payout_summary`, `admin_pending_payouts`, `mark_payout_settled`.
- **Object:** `admin_force_cancel()` exists with `auth_exec = true`; its body was **not** read in this pass.
- **Exploitation scenario:** protected by the admin check, unless `admins` is wrongly populated.
- **Recommended fix:** revoke from authenticated where the function is admin-console only, after the body is read. Audit `admins` contents.
- **Production-blocking:** No, if `admins` is verified.

---

## Part B: Unverified concerns (not confirmed; do not treat as findings)

| ID    | Concern                                                                                                                              | What is needed to verify                                                    |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| UV-01 | `request_subscription` may have side effects beyond the pending-payment insert.                                                      | Read full function body and all triggers on the subscription table.         |
| UV-02 | Contents of the `admins` table (who holds admin rights).                                                                             | Read-only count and list, with owner confirmation of expected names.        |
| UV-03 | Production storage bucket policies (KYC documents, proof photos).                                                                    | Read storage policies on production.                                        |
| UV-04 | `public_profiles` exposes `youth_owned_verified`. Earlier notes say no grant to anon or authenticated, but no column check was made. | Confirm view grants and whether the flag is reachable through another view. |
| UV-05 | `seller_kyc` stores ID number and bank details in plaintext, readable by the owning seller.                                          | Column types and RLS on `seller_kyc`. Encryption design needed.             |
| UV-06 | Gateway (API) request logging may retain request bodies, including ID numbers sent to SEC-03.                                        | Owner check of Supabase log retention settings.                             |
| UV-07 | `approve_withdrawal` comment says "funds actually leave the wallet now"; this is believed inaccurate.                                | Read full body and any payment integration (none expected).                 |

---

## Part C: Credentials and account (owner actions)

### SEC-11 — Exposed credentials

- **Severity:** High (operational). **Confirmed** that credentials were pasted into chat, which counts as exposure.
- **Environment:** production database password; staging webhook secret.
- **Recommended fix:** rotate both immediately. Confirm no secret is in source control (search repository). Do not paste replacements into chat.
- **Owner action.** Production-blocking: **Yes.**
- **Status:** Open. Owner.

### SEC-12 — GitHub 2FA

- **Severity:** Medium. Open. Owner action. Deadline 8 December 2026. Production-blocking: No (deadline).

---

## Summary

| Status                                      | Count | Items                                                             |
| ------------------------------------------- | ----- | ----------------------------------------------------------------- |
| Production-blocking, confirmed, draft ready | 4     | SEC-01, SEC-02, SEC-03, SEC-04 (with SEC-05 pending column check) |
| Production-blocking, fixed on staging only  | 1     | SEC-06                                                            |
| Production-blocking, owner action           | 1     | SEC-11                                                            |
| Confirmed, low or info                      | 4     | SEC-05 (column check open), SEC-08, SEC-09, SEC-10                |
| Unverified                                  | 7     | UV-01 to UV-07                                                    |

No item is marked fixed in production.
