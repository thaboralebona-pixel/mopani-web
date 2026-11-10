-- PHASE 4 / STEP 01 ROLLBACK. Staging only. Restores the grants that existed before PHASE4-01 (verified 10 Nov 2026).
-- Re-run only if the owner reverses the decision. Restoring SEC-01 reopens the withdrawal path.
-- Pre-state verified by dry run: authenticated had EXECUTE on request_withdrawal_v2, mark_payout_settled and request_subscription;
-- anon and authenticated had EXECUTE on sa_id_is_youth; approve_withdrawal and request_withdrawal had NO authenticated EXECUTE;
-- neither driver nor marshal view had an anon grant. Those are NOT re-granted here.
begin;
grant execute on function public.request_withdrawal_v2(numeric) to authenticated;
grant execute on function public.mark_payout_settled(uuid, numeric, text) to authenticated;
grant execute on function public.request_subscription(text) to authenticated;
grant execute on function public.sa_id_is_youth(text) to anon, authenticated;
grant insert, update, delete on public.seller_withdrawals to authenticated;
grant delete on public.seller_wallets to authenticated;
grant select on public.public_driver_profiles, public.public_marshal_profiles to authenticated;
commit;
