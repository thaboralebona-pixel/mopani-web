-- PHASE 4 / STEP 01: STAGING LOCKDOWN (SEC-01, SEC-02, SEC-03, SEC-04)
-- STATUS: NOT APPLIED. Awaiting owner approval of this exact file.
-- TARGET: mopani-staging only (exohydsjywelbhhswswh). Never run against production (ProjectX).
-- EFFECT: revokes execute and table grants only. No rows are changed or deleted. No table, column, policy or function body is altered.
-- HISTORY: seller_withdrawals, seller_wallets, wallet_transactions and all financial rows are preserved.
-- ORDER: run as one transaction. Run PHASE4-01-tests.sql first (dry run), then this file, then the tests again.

begin;

-- SEC-01: no new withdrawal requests; no direct settlement by signed-in users; no direct table writes to withdrawals.
revoke execute on function public.request_withdrawal_v2(numeric) from public, anon, authenticated;
revoke execute on function public.request_withdrawal(uuid, numeric) from public, anon, authenticated;
revoke execute on function public.mark_payout_settled(uuid, numeric, text) from public, anon, authenticated;
revoke execute on function public.approve_withdrawal(bigint) from public, anon, authenticated;
revoke insert, update, delete on public.seller_withdrawals from authenticated;
-- Note: seller_wallets INSERT is NOT revoked. create_wallet_for_seller() (invoker) inserts a wallet as the signing-up role.
-- Revoking it would break seller sign-up. DELETE on seller_wallets has no policy and no code path; revoked as hygiene.
revoke delete on public.seller_wallets from authenticated;

-- SEC-02: driver and marshal public views are not used by the application (verified in src/ and in the database).
revoke select on public.public_driver_profiles, public.public_marshal_profiles from anon, authenticated;

-- SEC-03: sa_id_is_youth is not part of the pilot. Function is retained; only execution is removed.
revoke execute on function public.sa_id_is_youth(text) from public, anon, authenticated;

-- SEC-04: subscriptions are not approved pilot functionality. Function is retained.
revoke execute on function public.request_subscription(text) from public, anon, authenticated;

commit;
