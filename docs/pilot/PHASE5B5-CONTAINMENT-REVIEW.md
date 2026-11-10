# Phase 5B-5: containment review

Date: 2026-11-10. Branch `feature/readiness-pass-1`.

**Status: preparation only.** The containment SQL is a draft and has not been executed. Decision 41 (execute containment) is **not approved**. All evidence below comes from `SELECT` queries and read-only tooling on production (`jpjjdzlhthvookllydai`) and staging (`exohydsjywelbhhswswh`). Neither database was changed.

Draft reviewed here: `docs/pilot/remediation/PHASE5B5-containment-package-DRAFT.sql`.

Labels: **Confirmed** (read this pass), **Earlier** (read earlier in Phase 5, not re-read), **Unresolved**.

---

## 1. Method and its limits

1. Every function and trigger function in schemas `public` and `private` was searched for statements that insert into, update or delete from: `seller_wallets`, `driver_wallets`, `marshal_wallet`, `platform_wallet`, `wallet_transactions`, `platform_revenue`, `driver_marshal_transactions`, `association_earnings`, `seller_withdrawals`.
2. From those writers, callers were followed upward by name through function source, five levels deep.
3. Separately checked: triggers on the financial tables and on `orders`; rules; functions in other schemas that mention a payout function; functions using dynamic SQL; all cron commands; all five deployed Edge Functions.

Limits (what would escape this method):

- A caller that builds a function name in dynamic SQL. The only functions using dynamic SQL are pgTAP test helpers; none mentions a payout function (**Confirmed**).
- Code outside the database: the external admin console (**Unresolved**) and any future Edge Function deployment.
- SQL typed by a privileged person.

The call graph is therefore **complete for database objects in `public` and `private` and for the five deployed Edge Functions**. It is not a claim about external systems.

---

## 2. Classification of every function found

All are owned by `postgres`. "App role" means `anon` or `authenticated`.

### 2.1 Direct writers of wallet credits (**Confirmed**)

| Function                                    | Security | EXECUTE                | Tables written                                                                                                                              |
| ------------------------------------------- | -------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `public._apply_route_payout(bigint)`        | DEFINER  | postgres, service_role | seller, driver, marshal, platform wallets; `wallet_transactions`; `platform_revenue`; `driver_marshal_transactions`; `association_earnings` |
| `public._apply_order_payout_legacy(bigint)` | DEFINER  | postgres, service_role | same set                                                                                                                                    |

The route payout **is** one of the two leaf functions. There is no third credit writer. `_apply_route_payout` has exactly one caller: `_apply_order_payout`.

### 2.2 Functions that call payout functions (**Confirmed**)

| Function                                                     | Security    | EXECUTE                                   | Calls                         | Depth from a writer |
| ------------------------------------------------------------ | ----------- | ----------------------------------------- | ----------------------------- | ------------------- |
| `public._apply_order_payout(bigint)`                         | DEFINER     | postgres, service_role                    | both leaves                   | 1                   |
| `public.confirm_delivery(bigint, text)`                      | DEFINER     | postgres, **authenticated**, service_role | `_apply_order_payout`         | 2                   |
| `public.complete_order(bigint, text)`                        | DEFINER     | postgres, service_role                    | `_apply_order_payout`         | 2                   |
| `public.resolve_dispute(bigint, text, text, text)`           | DEFINER     | postgres, service_role                    | `_apply_order_payout`         | 2                   |
| `private.auto_release_escrow()`                              | DEFINER     | postgres                                  | `_apply_order_payout`         | 2                   |
| `private.run_regression_suite()`                             | **INVOKER** | postgres                                  | `_apply_order_payout`         | 2                   |
| `public.confirm_order_delivery_by_phone(text, bigint, text)` | DEFINER     | postgres, service_role                    | `confirm_delivery`            | 3                   |
| `public.auto_release_escrow()`                               | DEFINER     | postgres, service_role                    | `private.auto_release_escrow` | 3                   |
| **`public.admin_resolve_dispute(bigint, text, text, text)`** | DEFINER     | postgres, **authenticated**, service_role | `resolve_dispute`             | 3                   |

`admin_resolve_dispute` is **new in this pass**. Its body checks `is_admin()`, then calls `resolve_dispute`, then writes an audit row. It was not in the previous draft.

### 2.3 Other wallet writers that are not order credits (**Confirmed**)

| Function                                          | Kind                                      | EXECUTE                                             | Effect                                         |
| ------------------------------------------------- | ----------------------------------------- | --------------------------------------------------- | ---------------------------------------------- |
| `public.refund_order(bigint, text)`               | DEFINER                                   | postgres, service_role                              | Debits wallets; negative revenue row           |
| `public.request_withdrawal_v2(numeric)`           | DEFINER                                   | postgres, authenticated, service_role               | Moves available to pending; inserts withdrawal |
| `public.request_withdrawal(uuid, numeric)`        | DEFINER                                   | postgres, service_role                              | Same, legacy                                   |
| `public.approve_withdrawal(bigint)`               | DEFINER                                   | postgres, service_role                              | Reduces pending; marks paid                    |
| `public.mark_payout_settled(uuid, numeric, text)` | DEFINER                                   | postgres, authenticated (admin check), service_role | Debits available                               |
| `public.create_wallet_for_seller()`               | trigger, INVOKER, attached to `profiles`  | PUBLIC                                              | Inserts a zero-balance wallet row              |
| `public.credit_wallet()`                          | trigger, INVOKER, **attached to nothing** | PUBLIC                                              | Would credit `seller_wallets`; dormant         |

Trigger functions cannot be called directly, so the PUBLIC grant on the last two is not a route. `credit_wallet` must never be re-attached.

### 2.4 Functions that only change order or delivery state

`create_order_v2`, `create_order`, `mark_collected`, `mark_dispatched`, `mark_received_by_marshal`, `mark_delivered`, `raise_dispute`, `set_delivery_address`, `admin_force_cancel`, `private._cancel_before_collection`, `accept_route_cargo_by_phone`, `record_collection_photo`, `record_proof_of_delivery`. None writes a wallet. `mark_delivered` creates the `delivered` precondition; the `holding` precondition is the column default.

### 2.5 Triggers, rules, jobs, Edge Functions

- Triggers on the nine financial tables: only `trigger_kyc_withdrawal_gate` and `trg_audit_withdrawal` on `seller_withdrawals`. Neither credits a wallet. Triggers on `orders`: twelve, none calls a writer (**Confirmed**).
- Rules in `public`: none. Functions in other schemas referencing payout functions: none (**Confirmed**).
- Cron: five jobs, all as `postgres`. Only job 2 reaches a payout (**Confirmed**).
- Edge Functions on production: `whatsapp-webhook` v8 (calls `confirm_order_delivery_by_phone`), `dispatch-whatsapp` v7 (no payout call), `stripe-webhook` v7 (returns 410, no database access): **Confirmed** by reading deployed source today. `dispatch-notification` v12 and `lindi-chat` v10: **Earlier**, no payout call.

---

## 3. Routes and how each is closed

| Route  | Entry                                                                                                    | Callable by                                | Executes as        | Closed by      |
| ------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ------------------ | -------------- |
| R1     | `whatsapp-webhook` → `confirm_order_delivery_by_phone`                                                   | service_role                               | postgres (definer) | B2             |
| R2     | RPC `confirm_delivery`                                                                                   | authenticated                              | postgres           | B1             |
| R3     | cron job 2 → `private.auto_release_escrow`                                                               | cron                                       | postgres           | A1             |
| R4a    | `complete_order`                                                                                         | service_role                               | postgres           | B3             |
| R4b    | `resolve_dispute`                                                                                        | service_role                               | postgres           | B4             |
| **R8** | `admin_resolve_dispute`                                                                                  | authenticated (active admin), service_role | postgres           | **B5**         |
| R7     | `public.auto_release_escrow()`                                                                           | service_role                               | postgres           | B6             |
| R5a    | `_apply_order_payout`                                                                                    | service_role                               | postgres           | B7             |
| R5b    | either leaf directly                                                                                     | service_role                               | postgres           | B8, B9         |
| R6     | SQL as `postgres` or `supabase_admin`; any Edge Function using `SUPABASE_DB_URL`; `run_regression_suite` | privileged                                 | caller             | **Not closed** |

Final list: **one cron unschedule and nine revokes** (the previous draft had eight).

---

## 4. Nested execution: the rule that decides the list

PostgreSQL checks EXECUTE permission against the **current user at each call**. Inside a SECURITY DEFINER function the current user is the function's **owner**.

Consequences here:

1. Every function in the path is SECURITY DEFINER and owned by `postgres`, except `run_regression_suite` (INVOKER, postgres only).
2. `postgres` holds EXECUTE on all of them as owner. A revoke from `service_role` or `authenticated` does not touch that.
3. So a child function stays callable **from inside any parent**, whatever is revoked from other roles. Revoking only a child does not close a route whose parent is still callable.

Worked example, the gap in the previous draft:

- Previous draft revoked `resolve_dispute` from `service_role`.
- `admin_resolve_dispute` stayed executable by `authenticated`.
- An admin calling `admin_resolve_dispute` runs it as `postgres`, which calls `resolve_dispute` as `postgres`, which calls the payout as `postgres`. **Still open.**
- Fix: revoke the outermost callable function as well (B5).

After the nine revokes, the table below holds.

| Function                          | Callable externally by | Still callable internally by                                    |
| --------------------------------- | ---------------------- | --------------------------------------------------------------- |
| `confirm_delivery`                | no app or service role | `confirm_order_delivery_by_phone` (itself not callable)         |
| `confirm_order_delivery_by_phone` | none                   | nothing                                                         |
| `complete_order`                  | none                   | nothing                                                         |
| `resolve_dispute`                 | none                   | `admin_resolve_dispute` (itself not callable)                   |
| `admin_resolve_dispute`           | none                   | nothing                                                         |
| `public.auto_release_escrow`      | none                   | nothing                                                         |
| `private.auto_release_escrow`     | never was              | `public.auto_release_escrow` (not callable); cron (unscheduled) |
| `_apply_order_payout`             | none                   | the five parents (none callable)                                |
| both leaves                       | none                   | `_apply_order_payout`                                           |

No legitimate internal call is broken by a revoke. What is lost is the **entry points**, which is the purpose. The functions that lose their only use while containment is in force:

- Dispute resolution (both outcomes). Consequence: disputes need an owner-approved manual process. A safe alternative that keeps the refund outcome would require a new function, which is not introduced on production in this package.
- WhatsApp receipt confirmation: see `WHATSAPP-RECEIPT-CONFIRMATION-COPY-DRAFT.md`.

---

## 5. What changed from the Phase 5B-4 draft

| Item              | Phase 5B-4         | Phase 5B-5                                                                                   |
| ----------------- | ------------------ | -------------------------------------------------------------------------------------------- |
| Revokes           | 8                  | **9** (adds `admin_resolve_dispute`)                                                         |
| Route list        | R1 to R7           | adds **R8**                                                                                  |
| Privileged routes | "SQL as postgres"  | adds `SUPABASE_DB_URL` in every Edge Function, and `run_regression_suite`                    |
| Post-check        | privilege matrix   | adds V6, a recursive check that no caller of a leaf is executable by any app or service role |
| Snapshot          | prose              | exact ACL per function and full cron row                                                     |
| Effect list       | WhatsApp, disputes | adds: **both** dispute outcomes stop; what keeps working                                     |
| Other writers     | not listed         | section E (refund and withdrawal functions), outside the package                             |

---

## 6. Remaining routes this package cannot contain

1. **Privileged SQL.** `postgres`, `supabase_admin`, the dashboard SQL editor, the database password.
2. **`SUPABASE_DB_URL`.** Supabase provides this direct database URL to every Edge Function by default ([Supabase docs](https://supabase.com/docs/guides/functions/secrets)). A function that used it would not be bound by any `service_role` revoke. No deployed function uses it today.
3. **External admin console.** Unknown code, unknown role.
4. **Re-creation.** A new cron job, a new wrapper function, or a re-grant by anyone with owner rights.
5. **Staging.** Staging has the same functions and grants but no cron. This package is written for production; staging would need the nine revokes only.

Privileged access is a separate financial-control risk: who holds the dashboard and database credentials, and how changes are reviewed and logged.

---

## 7. Other observations from this pass

- **pgTAP is installed in `public` on production.** 22 of its helper functions use dynamic SQL and are executable by `authenticated`. They run as the caller, so they do not raise privileges, but they let a signed-in user run arbitrary SQL text with their own rights through the API. Recommend moving pgTAP out of the exposed schema or removing it from production (SEC-51, separate decision).
- **`service_role` can read `vault.decrypted_secrets`** (**Confirmed**). Any secret placed in the database vault is readable by every Edge Function.
- **Staging matches production** on the ACL of every function in section 2. Source hashes match for every function compared in Phase 5B-4. Five were not hash-compared across environments: `admin_resolve_dispute`, `request_withdrawal`, `create_wallet_for_seller`, `credit_wallet`, `private.run_regression_suite` (**Unresolved**, low risk).

## 8. Verification added on 2026-11-10 (read-only)

- Cron (production, `cron.job`): five jobs confirmed. Jobid 2 `escrow-auto-release-72h`; jobids 3, 4, 5, 6 are `background-sweeps`, `whatsapp-dispatch`, `founder-digest-1800-sast` and `auto-cancel-undispatched`, all owner postgres, all active. The draft's post-check V2 expects these IDs, and they match. Only job 2 reaches a payout.
- Source search of `public` and `private` for `complete_order`, `resolve_dispute`, `admin_resolve_dispute`, `auto_release_escrow`, `confirm_delivery` and `confirm_order_delivery_by_phone`: no function calls `complete_order`. The draft previously said its only caller was the retired Stripe webhook. That is now stated as unidentified in the database, and the Stripe webhook returns 410. This is the only text correction in this pass.
- `private.run_regression_suite` and `credit_wallet` match the name search. `credit_wallet` is the dormant trigger function from section 2.3. The regression suite is the R6 item in section 6.
- The draft `PHASE5B5-containment-package-DRAFT.sql` was corrected in three places: the full cron snapshot is recorded as the restore target, the V3 pointer names the function-privilege query, and the `complete_order` caller statement is corrected. No executable statement was added or uncommented.

Nothing in this document authorises a database change.
