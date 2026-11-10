-- =============================================================================
-- PHASE 5B CONTAINMENT: PRODUCTION PAYOUT FREEZE (DRAFT, NOT APPLIED)
-- =============================================================================
-- STATUS:   DRAFT. NOT EXECUTED ON ANY ENVIRONMENT. Requires the owner's written
--           approval of this exact file before any production run.
-- TARGET:   Production project only after approval. Staging rehearsal first
--           (staging must be applied to its own project, never through production).
-- PURPOSE:  While payments are disabled, no route may move ledger money:
--             1. WhatsApp "Confirm Receipt" -> confirm_order_delivery_by_phone -> confirm_delivery
--             2. Direct RPC confirm_delivery by any signed-in buyer (authenticated EXECUTE)
--             3. Hourly cron escrow-auto-release-72h -> private.auto_release_escrow
--             4. complete_order / resolve_dispute (service role) -> _apply_order_payout
--           Every route ends in public._apply_order_payout. Guarding that one function
--           plus removing buyer EXECUTE on confirm_delivery closes all four.
--
-- THIS IS CONTAINMENT, NOT THE PERMANENT CONTROL. payments_live is a switch, not
-- proof of payment. Before any payout is re-enabled, each payout must require
-- order-specific verified payment evidence (provider reference, amount matched to
-- the order total, atomic write). That design is a separate, reviewed change.
--
-- DOES NOT:  change any existing order, wallet, ledger row or balance;
--            release the held order 96 (R50); touch dispute 9; delete any cron job
--            (cron unschedule is STEP 3, separately approved, see below).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- STEP 1. Fail closed inside the one function every payout passes through.
-- Body is the verified production definition (read-only, Phase 5B) with a guard
-- added at the top. The dispute check and the route/legacy dispatch are unchanged.
-- -----------------------------------------------------------------------------
create or replace function public._apply_order_payout(p_order_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
  -- PHASE 5B GUARD: fail closed while payments are not live.
  IF COALESCE((SELECT value FROM app_config WHERE key = 'payments_live'), 'false') <> 'true' THEN
    RAISE EXCEPTION 'Payouts are disabled while payments are not live (order %)', p_order_id;
  END IF;

  IF EXISTS (SELECT 1 FROM disputes
              WHERE order_id = p_order_id
                AND status IN ('open','under_review','escalated')) THEN
    RAISE EXCEPTION 'Order % has an open dispute. Payment stays frozen until admin resolves it.', p_order_id;
  END IF;
  IF EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND route_id IS NOT NULL) THEN
    PERFORM public._apply_route_payout(p_order_id);
  ELSE
    PERFORM public._apply_order_payout_legacy(p_order_id);
  END IF;
END $function$;

-- -----------------------------------------------------------------------------
-- STEP 2. Remove buyer-callable EXECUTE on confirm_delivery.
-- No file in src/ calls it (frontend calls only quote_order, products, delivery_routes).
-- The WhatsApp path still works: confirm_order_delivery_by_phone is owned by the
-- definer role, which keeps EXECUTE on the function it calls.
-- -----------------------------------------------------------------------------
revoke execute on function public.confirm_delivery(bigint, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- STEP 3. (SEPARATE APPROVAL) Stop the hourly auto-release job.
-- Step 1 already makes it fail, but each run would write an 'auto_release_failed'
-- audit row every hour. Unscheduling is cleaner. Run only on explicit owner approval.
-- -----------------------------------------------------------------------------
-- select cron.unschedule('escrow-auto-release-72h');

-- -----------------------------------------------------------------------------
-- VERIFICATION (run inside this transaction; the block raises and rolls back
-- so the production state is unchanged after verification).
-- -----------------------------------------------------------------------------
do $verify$
declare
  v_guard boolean;
  v_buyer_exec boolean;
begin
  select prosrc like '%Payouts are disabled while payments are not live%'
    into v_guard
    from pg_proc where oid = 'public._apply_order_payout(bigint)'::regprocedure;
  v_buyer_exec := has_function_privilege('authenticated', 'public.confirm_delivery(bigint,text)', 'EXECUTE');

  if not v_guard then raise exception 'VERIFY FAIL: payout guard not present'; end if;
  if v_buyer_exec then raise exception 'VERIFY FAIL: authenticated still has EXECUTE on confirm_delivery'; end if;
  raise exception 'VERIFY OK (dry run): guard present, buyer EXECUTE removed. Rolling back by design.';
end
$verify$;

-- The block above always raises, so this transaction rolls back and nothing persists.
-- For the real apply, replace the final RAISE with a normal exit, then:  commit;
rollback;

-- =============================================================================
-- TESTS (run on STAGING only, before any production approval). Each must hold.
--  T1  payments_live = 'false': EXECUTE _apply_order_payout on a delivered, holding
--      order raises "Payouts are disabled"; seller/driver/marshal/platform wallet
--      totals and wallet_transactions count are unchanged.
--  T2  payments_live = 'false': confirm_order_delivery_by_phone (service role) returns
--      ok=false with reason confirm_failed; order stays delivered/holding; no ledger row.
--  T3  authenticated buyer calling rpc confirm_delivery -> permission denied.
--  T4  anon -> permission denied (anon never had EXECUTE; re-check).
--  T5  escrow-auto-release run (select private.auto_release_escrow()) returns 0 and
--      writes only 'auto_release_failed' audit rows; no balance changes.
--  T6  payments_live = 'true' on a staging fixture with NO payment evidence: payout
--      still allowed by this containment ONLY if disputes are clear. This shows why
--      the containment is NOT the permanent control; it must be paired with the
--      verified-payment design before any real money flows.
--  T7  dispute path: order with escalated dispute: payout still refused (existing rule).
--  T8  Roles: admin, seller, driver and marshal calling confirm_delivery directly,
--      and each attempting _apply_order_payout (no grant): all refused.
--
-- ROLLBACK (exact pre-state, verified by read-only query on production, Phase 5B):
--   create or replace function public._apply_order_payout(p_order_id bigint) ...
--     -> restore the body WITHOUT the first IF block (the function as read on 2026-11-10,
--        identical to the body shown in docs/pilot/PHASE5B-PAYOUT-CONTAINMENT.md, section 3).
--   grant execute on function public.confirm_delivery(bigint, text) to authenticated;
--   -- if STEP 3 ran:  select cron.schedule('escrow-auto-release-72h', '0 * * * *',
--                       'SELECT private.auto_release_escrow();');
-- =============================================================================
