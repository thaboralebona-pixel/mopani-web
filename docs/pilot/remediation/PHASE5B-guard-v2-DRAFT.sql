-- =============================================================================
-- PHASE 5B: PAYOUT GUARD v2 (DESIGN DRAFT). NOT EXECUTED. NOT APPROVED.
-- Supersedes the payments_live-only guard in PHASE5B-containment-DRAFT.sql step 1
-- for any step beyond containment. It cannot be applied as written: it references
-- table payment_evidence, which does not exist yet. Until it exists, the guard
-- below fails closed for every order, which is the intended containment state.
-- Staging rehearsal and written owner approval are required before any production use.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Verified payment evidence. Written ONLY by the signed payment-provider
--    webhook under the service role. No app role can insert, update or delete.
-- -----------------------------------------------------------------------------
create table if not exists public.payment_evidence (
  id                bigserial primary key,
  order_id          bigint not null references public.orders(id),
  provider          text   not null check (provider in ('paystack')),
  provider_ref      text   not null unique,            -- provider transaction reference
  amount_cents      bigint not null check (amount_cents > 0),
  currency          text   not null check (currency = 'ZAR'),
  status            text   not null check (status = 'verified'),
  event_hash        text   not null,                   -- hash of the signed event body; never the body
  verified_at       timestamptz not null,
  created_at        timestamptz not null default now(),
  constraint one_verified_payment_per_order unique (order_id)
);

alter table public.payment_evidence enable row level security;
-- No policies for anon or authenticated: with RLS enabled and no policy, app roles
-- have no access. Service role bypasses RLS and is the only writer.
revoke all on public.payment_evidence from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Guard inside the single payout entry point. Checks, in order:
--    a) payments_live is true (switch only; not sufficient alone)
--    b) a verified payment row exists for this order
--    c) the recorded amount equals the order total in cents (trusted DB value)
--    d) the order is not already released (duplicate release)
--    e) no open dispute
--    f) every allocation leg has a recipient or is recorded as pending
--    g) the whole payout runs in the caller's transaction; any failure rolls back
-- Body of the existing route/legacy dispatch is NOT changed here; this only adds
-- gates. Requires a reviewed change to _apply_order_payout_legacy and
-- _apply_route_payout so that missing legs are written as pending, not dropped.
-- -----------------------------------------------------------------------------
create or replace function public._apply_order_payout(p_order_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_total_cents bigint;
  v_escrow      text;
  v_amount      bigint;
  v_currency    text;
BEGIN
  -- a) switch
  IF COALESCE((SELECT value FROM app_config WHERE key = 'payments_live'), 'false') <> 'true' THEN
    RAISE EXCEPTION 'Payout refused: payments not live (order %)', p_order_id;
  END IF;

  -- e) open dispute (unchanged rule)
  IF EXISTS (SELECT 1 FROM disputes
              WHERE order_id = p_order_id
                AND status IN ('open','under_review','escalated')) THEN
    RAISE EXCEPTION 'Payout refused: open dispute on order %', p_order_id;
  END IF;

  -- trusted order values, row-locked
  SELECT round(total_amount * 100)::bigint, escrow_status
    INTO v_total_cents, v_escrow
    FROM orders WHERE id = p_order_id FOR UPDATE;
  IF v_total_cents IS NULL OR v_total_cents <= 0 THEN
    RAISE EXCEPTION 'Payout refused: order % has no positive total', p_order_id;
  END IF;

  -- d) duplicate release
  IF v_escrow <> 'holding' THEN
    RAISE EXCEPTION 'Payout refused: order % escrow is %, not holding', p_order_id, v_escrow;
  END IF;

  -- b), c) verified payment evidence that matches the trusted amount and currency
  SELECT amount_cents, currency INTO v_amount, v_currency
    FROM payment_evidence
   WHERE order_id = p_order_id AND status = 'verified';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payout refused: no verified payment evidence for order %', p_order_id;
  END IF;
  IF v_amount <> v_total_cents OR v_currency <> 'ZAR' THEN
    RAISE EXCEPTION 'Payout refused: payment % does not match order % total', v_amount, p_order_id;
  END IF;

  -- f) recipient legs are checked by the dispatch below (to be reviewed; see doc)
  IF EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND route_id IS NOT NULL) THEN
    PERFORM public._apply_route_payout(p_order_id);
  ELSE
    PERFORM public._apply_order_payout_legacy(p_order_id);
  END IF;

  -- g) audit of the basis for the release, written in the same transaction
  INSERT INTO admin_audit_log (admin_id, action, target_table, target_id, after_data)
  VALUES (NULL, 'payout_guard_passed', 'orders', p_order_id::text,
          jsonb_build_object('amount_cents', v_amount, 'currency', v_currency));
END $function$;

-- -----------------------------------------------------------------------------
-- 3. Verification (to run on STAGING after a rehearsal; not on production):
--    * payment_evidence has RLS enabled and zero policies for anon/authenticated
--    * has_table_privilege('authenticated','public.payment_evidence','INSERT') = false
--    * guard raises for an order with no evidence (T-P1 in PHASE5B-GUARD-AND-TESTS.md)
-- Rollback: restore the body from PHASE5B-containment-DRAFT.sql step 1 (no
-- payment_evidence dependency) or the original body documented in PHASE5B-PAYOUT-CONTAINMENT.md
-- section 3; drop table payment_evidence only if empty and no code depends on it.
-- =============================================================================
