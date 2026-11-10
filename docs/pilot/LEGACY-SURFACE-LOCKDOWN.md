# Legacy surface and identity function review (SEC-03 to SEC-06)

Evidence source: read-only queries against **staging** (project `mopani-staging`), 10 Nov 2026. Production was not inspected in this pass. Nothing was changed. Nothing is deleted. Frontend search: `src/` contains no call to any function below; the only RPCs are `quote_order`, and the only table reads are `products` and `delivery_routes`.

Important: "the frontend does not call it" is not a security control. Every function below is reachable with the public anon key through `/rest/v1/rpc/<name>` if the grant allows it.

## 1. sa_id_is_youth (SEC-03, confirmed)

| Property  | Evidence                                                                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Signature | `sa_id_is_youth(p_id_number text)`                                                                                                                |
| Security  | SECURITY INVOKER (`security_definer = false`), volatility IMMUTABLE                                                                               |
| Grants    | **anon: EXECUTE true. authenticated: EXECUTE true.**                                                                                              |
| Body      | Reads the first six digits as a date of birth, returns true if the age is 18–35, NULL if malformed. No table access, no insert, no log statement. |

What it does with an ID number: it receives the full string, derives a date of birth from the first six digits, and returns one boolean. It does not store or log the number inside the function.

Why it still matters:

- **Oracle for personal data.** The function turns any supplied ID number into a true/false "youth" attribute. An anonymous caller can test any number, or enumerate date-of-birth ranges, and learn which ones fall in the 18–35 band. The output is only a boolean, but the input is the sensitive value, and the caller controls it.
- **Raw input leaves the client.** Any caller that sends the number over the API has already transmitted the ID number to the database and its logs (API gateway logs record request bodies only if logging is enabled, so this is unverified for production).
- **No pilot requirement.** The pilot does not verify youth status. Mopani does not need this function for launch, and no owner decision requires it. The owner's starting position (outside pilot scope, not publicly callable) is consistent with this review.
- Related but separate: `compute_verified_youth` (not callable by anon or authenticated, per staging) stores a `verified_youth` flag on `seller_kyc`. Any plaintext ID number or bank detail stored in `seller_kyc` is a separate finding (SEC-06 below).

Recommended fix (staging draft `SEC-03-sa-id-youth-revoke.sql`): `revoke execute on function public.sa_id_is_youth(text) from public, anon, authenticated;`. Keep the function (do not drop). Check for dependents first (`pg_depend` and a catalogue text search for `sa_id_is_youth`). Rollback: re-grant to authenticated and anon.

## 2. Legacy surface table

| Feature                | Function(s)                                                                            | Anon exec                                            | Auth exec                                 | Modifies data                     | Financial effect           | Frontend use | Pilot required?                       | Proposed action                                                                                     |
| ---------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------- | ----------------------------------------- | --------------------------------- | -------------------------- | ------------ | ------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Withdrawals            | `request_withdrawal_v2(numeric)`                                                       | no                                                   | **yes**                                   | yes (available → pending)         | **yes, creates liability** | none         | no                                    | Revoke (SEC-01, separate draft)                                                                     |
| Withdrawals            | `request_withdrawal(uuid, numeric)`                                                    | no                                                   | no                                        | —                                 | —                          | none         | no                                    | Retain; no grant (verify it is not reachable via another route)                                     |
| Withdrawals settlement | `approve_withdrawal(bigint)`                                                           | no                                                   | no                                        | yes                               | yes                        | none         | no                                    | Retain, block until double-settlement analysis is done                                              |
| Withdrawals settlement | `mark_payout_settled(uuid, numeric, text)`                                             | no                                                   | **yes** (guarded by `is_admin()` in body) | yes (debits available)            | **yes**                    | none         | no                                    | Revoke from authenticated; admin path via service role only (owner decision)                        |
| Subscriptions          | `request_subscription(text)`                                                           | no                                                   | **yes**                                   | yes (inserts pending payment row) | potential, unconfirmed     | none         | no                                    | Revoke from authenticated (SEC-04)                                                                  |
| Subscriptions          | `activate_subscription(uuid, text, timestamptz)`                                       | no                                                   | no                                        | yes                               | yes                        | none         | no                                    | Retain, no grant                                                                                    |
| KYC                    | `enforce_kyc_on_withdrawal`, `audit_kyc_change`, `emit_trust_on_kyc`                   | trigger-only or no                                   | no / trigger                              | yes                               | no                         | none         | seller KYC needed for onboarding only | Retain as triggers; no direct execute                                                               |
| Youth verification     | `sa_id_is_youth(text)`                                                                 | **yes**                                              | **yes**                                   | no                                | no                         | none         | no                                    | Revoke (SEC-03)                                                                                     |
| Youth verification     | `compute_verified_youth()`                                                             | no                                                   | no                                        | yes                               | no                         | none         | no                                    | Retain                                                                                              |
| Referrals              | `generate_referral_code()`                                                             | yes                                                  | yes                                       | no (returns value)                | no                         | none         | no                                    | Low risk; retain or revoke from anon. Confirm no referral table rows are created                    |
| Listing fees           | `charge_listing_fee()` (trigger on products)                                           | yes (trigger function, not callable as a normal RPC) | yes                                       | yes (writes fee rows)             | fee amounts R0 on staging  | none         | no                                    | Confirm trigger cannot be invoked directly; retain; check tier amounts before any pilot listing fee |
| Admin                  | `admin_approve`, `admin_set_driver_*`, `admin_payout_summary`, `admin_pending_payouts` | no                                                   | yes                                       | some                              | some                       | none         | admin only                            | Retain; each body checks `is_admin()`. Unverified: contents of `admins` table                       |

Staging row counts (read at 10 Nov): withdrawals 0, subscriptions 0, referrals 0, listing-fee payments 0, listing fees R0, KYC rows 2.

## 3. Lockdown plan (for owner approval; no change applied)

Order of work, staging first:

1. SEC-01 `request_withdrawal_v2` revoke (draft exists; dry run done and rolled back).
2. SEC-03 `sa_id_is_youth` revoke from anon and authenticated.
3. SEC-04 `request_subscription` revoke from authenticated.
4. Decide on `mark_payout_settled` and `approve_withdrawal` (two unlinked settlement paths): restrict to service role or remove the grant, after a dependency check.
5. Re-run the grant matrix for every function in section 2 and record the results.

Each step: dependency check, before/after privileges query, rollback statement, and a test that an anonymous or buyer-role call returns a permission error.

Not to do without approval: drop any function, drop any table, change `is_admin()`, change RLS.

## 4. Owner decision needed

- Approve SEC-03 (revoke sa_id_is_youth) for staging.
- Decide whether youth verification is removed from the product permanently or kept for a later phase.
- Decide who can settle withdrawals (admin role only, or no settlement path during the pilot).
