-- =============================================================================
-- PHASE 5B-5 PAYMENT EVIDENCE AND PAYOUT GUARD: SQL DRAFT
-- =============================================================================
--  ****  DRAFT. NOT APPROVED. NOT EXECUTED. NOT PARSED BY POSTGRESQL.  ****
--  Design: docs/pilot/PHASE5B5-GUARD-ARCHITECTURE.md
--  This file has never been run on any database. It will contain mistakes that
--  only a staging rehearsal can find. Applying it anywhere needs separate written
--  owner approval. It must be rehearsed on staging before production is considered.
--
--  The first statement below aborts, so the file cannot be applied by accident.
-- =============================================================================

do $$ begin
  raise exception 'PHASE5B5 payment guard is a DRAFT and is not approved for execution';
end $$;

begin;

-- -----------------------------------------------------------------------------
-- 0. Schema and default privileges (D8). Same migration, before any table exists.
--    Schema "pay" must NOT be added to the API's exposed schemas.
-- -----------------------------------------------------------------------------
create schema if not exists pay authorization postgres;
revoke all on schema pay from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema pay
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema pay
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema pay
  revoke all on functions from public, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 1. Writer role (D2, option A). NO PASSWORD HERE. The owner sets the password
--    out of band and stores it only in the separate payments project.
-- -----------------------------------------------------------------------------
create role payment_writer login noinherit nobypassrls connection limit 5;
grant usage on schema pay to payment_writer;
-- deliberately NOT granted to authenticator: the API cannot switch to this role.
grant usage on schema pay to service_role;      -- read-only reporting; see table grants

-- -----------------------------------------------------------------------------
-- 2. Append-only helper
-- -----------------------------------------------------------------------------
create function pay.reject_change() returns trigger
language plpgsql as $$
begin
  raise exception 'pay.% is append-only (% refused)', tg_table_name, tg_op;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Payment intents: the database issues the reference and the amount (D1, D7)
-- -----------------------------------------------------------------------------
create table pay.payment_intents (
  id            bigint generated always as identity primary key,
  order_id      bigint not null references public.orders(id) on delete restrict,
  buyer_id      uuid   not null,
  reference     text   not null unique,
  amount_cents  bigint not null check (amount_cents > 0),
  currency      text   not null check (currency = 'ZAR'),
  status        text   not null default 'open'
                check (status in ('open','verified','reconciling','failed','expired','refunded','charged_back','settled','reconciled')),
  created_at    timestamptz not null default now(),
  closed_at     timestamptz
);
-- one live intent per order: a second charge cannot be started while one is live
create unique index payment_intents_one_live_per_order
  on pay.payment_intents (order_id)
  where status in ('open','verified','reconciling','settled','reconciled');

-- -----------------------------------------------------------------------------
-- 4. Provider events: every webhook delivery, good or bad (D1.8, D7)
-- -----------------------------------------------------------------------------
create table pay.provider_events (
  id                 bigint generated always as identity primary key,
  provider           text not null check (provider = 'paystack'),
  provider_event_id  text not null,
  event_type         text not null,
  reference          text,
  body_sha256        text not null check (body_sha256 ~ '^[0-9a-f]{64}$'),
  signature_valid    boolean not null,
  signing_key_id     text,
  outcome            text not null
                     check (outcome in ('rejected_signature','provider_verify_failed','mismatch','duplicate','recorded','ignored')),
  detail             text,
  received_at        timestamptz not null default now(),
  unique (provider, provider_event_id)
);

-- -----------------------------------------------------------------------------
-- 5. Payment evidence: one verified row per order (D1)
-- -----------------------------------------------------------------------------
create table pay.payment_evidence (
  id                       bigint generated always as identity primary key,
  intent_id                bigint not null unique references pay.payment_intents(id) on delete restrict,
  order_id                 bigint not null unique references public.orders(id) on delete restrict,
  buyer_id                 uuid   not null,
  provider                 text   not null check (provider = 'paystack'),
  provider_transaction_id  text   not null,
  provider_reference       text   not null unique,
  provider_event_id        text   not null,
  amount_cents             bigint not null check (amount_cents > 0),
  currency                 text   not null check (currency = 'ZAR'),
  provider_status          text   not null check (provider_status = 'success'),
  provider_paid_at         timestamptz not null,
  webhook_body_sha256      text   not null check (webhook_body_sha256 ~ '^[0-9a-f]{64}$'),
  verify_response_sha256   text   not null check (verify_response_sha256 ~ '^[0-9a-f]{64}$'),
  signing_key_id           text   not null,
  verifier_build           text   not null,
  written_by               name   not null default session_user,
  verified_at              timestamptz not null default now(),
  unique (provider, provider_transaction_id)
);

-- status history for evidence: verified, refunded, charged_back, settled, reconciled
create table pay.evidence_events (
  id           bigint generated always as identity primary key,
  evidence_id  bigint not null references pay.payment_evidence(id) on delete restrict,
  event        text   not null check (event in ('verified','refund_partial','refunded','charged_back','settled','reconciled','reconcile_mismatch')),
  amount_cents bigint,
  provider_ref text,
  detail       text,
  written_by   name not null default session_user,
  created_at   timestamptz not null default now(),
  unique (evidence_id, event, provider_ref)
);

-- -----------------------------------------------------------------------------
-- 6. Allocation legs (D5): one row per intended leg, always
-- -----------------------------------------------------------------------------
create table pay.allocation_legs (
  id              bigint generated always as identity primary key,
  order_id        bigint not null references public.orders(id) on delete restrict,
  evidence_id     bigint not null references pay.payment_evidence(id) on delete restrict,
  leg             text   not null check (leg in ('seller','platform','driver','marshal','association','card_fee')),
  recipient_kind  text   not null check (recipient_kind in ('seller','platform','driver','marshal','association','reserve','suspense')),
  recipient_ref   text,                         -- seller uuid, driver id, marshal id, partner id; NULL for suspense/platform/reserve
  amount_cents    bigint not null,              -- positive for allocation, negative for reversal, 0 allowed
  reverses_leg_id bigint references pay.allocation_legs(id) on delete restrict,
  refund_id       bigint,                       -- set on reversal rows
  reason          text,
  created_at      timestamptz not null default now(),
  check ((reverses_leg_id is null and amount_cents >= 0) or (reverses_leg_id is not null and amount_cents <= 0)),
  check (recipient_kind <> 'suspense' or recipient_ref is null)
);
create unique index allocation_legs_one_per_order_leg
  on pay.allocation_legs (order_id, leg) where reverses_leg_id is null;
create unique index allocation_legs_one_reversal_per_refund
  on pay.allocation_legs (reverses_leg_id, refund_id) where reverses_leg_id is not null;

create table pay.allocation_events (
  id          bigint generated always as identity primary key,
  leg_id      bigint not null references pay.allocation_legs(id) on delete restrict,
  state       text   not null check (state in ('allocated','pending_recipient','not_applicable','released_internal',
                                               'submitted_external','externally_paid','failed','reversed','reconciled','recipient_assigned')),
  detail      text,
  actor       uuid,
  written_by  name not null default session_user,
  created_at  timestamptz not null default now()
);

-- named suspense balance: never platform revenue
create table pay.suspense_balance (
  id            int primary key check (id = 1),
  balance_cents bigint not null default 0 check (balance_cents >= 0)
);
insert into pay.suspense_balance (id) values (1);

-- -----------------------------------------------------------------------------
-- 7. Refunds and external settlements (D6, D7)
-- -----------------------------------------------------------------------------
create table pay.refunds (
  id                  bigint generated always as identity primary key,
  evidence_id         bigint not null references pay.payment_evidence(id) on delete restrict,
  provider_refund_id  text   not null unique,
  amount_cents        bigint not null check (amount_cents > 0),
  kind                text   not null check (kind in ('refund','chargeback')),
  status              text   not null check (status in ('requested','provider_confirmed','failed','needs_recovery','applied')),
  created_at          timestamptz not null default now()
);

create table pay.settlements (
  id               bigint generated always as identity primary key,
  idempotency_key  text   not null unique,        -- created BEFORE the transfer request
  recipient_kind   text   not null check (recipient_kind in ('seller','driver','marshal','association')),
  recipient_ref    text   not null,
  amount_cents     bigint not null check (amount_cents > 0),
  provider_ref     text unique,
  status           text   not null check (status in ('created','submitted','paid','failed')),
  created_at       timestamptz not null default now()
);
create table pay.settlement_legs (
  settlement_id bigint not null references pay.settlements(id) on delete restrict,
  leg_id        bigint not null unique references pay.allocation_legs(id) on delete restrict,
  primary key (settlement_id, leg_id)
);

-- -----------------------------------------------------------------------------
-- 8. Privileges, RLS, immutability for every pay table
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['payment_intents','provider_events','payment_evidence','evidence_events',
                           'allocation_legs','allocation_events','suspense_balance','refunds',
                           'settlements','settlement_legs']
  loop
    execute format('revoke all on pay.%I from public, anon, authenticated, service_role, payment_writer', t);
    execute format('grant select on pay.%I to service_role', t);           -- read-only reporting
    execute format('alter table pay.%I enable row level security', t);
    execute format('alter table pay.%I force row level security', t);
  end loop;
end $$;
-- No policies are created: with forced RLS, only the owner inside SECURITY DEFINER
-- functions (and roles with BYPASSRLS) can read or write. service_role has
-- BYPASSRLS, which is why its table privilege is SELECT only.

create trigger no_change before update or delete on pay.payment_evidence  for each row execute function pay.reject_change();
create trigger no_change before update or delete on pay.evidence_events   for each row execute function pay.reject_change();
create trigger no_change before update or delete on pay.provider_events   for each row execute function pay.reject_change();
create trigger no_change before update or delete on pay.allocation_legs   for each row execute function pay.reject_change();
create trigger no_change before update or delete on pay.allocation_events for each row execute function pay.reject_change();

-- -----------------------------------------------------------------------------
-- 9. Escrow state (D3): new orders start in awaiting_payment
-- -----------------------------------------------------------------------------
alter table public.orders drop constraint orders_escrow_status_check;
alter table public.orders add constraint orders_escrow_status_check
  check (escrow_status in ('awaiting_payment','holding','released','disputed','refunded','cancelled'));
alter table public.orders alter column escrow_status set default 'awaiting_payment';

-- holding is impossible without evidence, whoever writes the row
create function pay.enforce_holding_has_evidence() returns trigger
language plpgsql security definer set search_path = pay, public as $$
begin
  if new.escrow_status = 'holding'
     and (tg_op = 'INSERT' or old.escrow_status is distinct from 'holding')
     and not exists (select 1 from pay.payment_evidence e where e.order_id = new.id) then
    raise exception 'Order % cannot enter holding without verified payment evidence', new.id;
  end if;
  return new;
end $$;
create trigger trg_holding_needs_evidence
  before insert or update of escrow_status on public.orders
  for each row execute function pay.enforce_holding_has_evidence();

-- REQUIRED FOLLOW-ON CHANGES (not written in this draft; each tests escrow = 'holding'
-- for orders that will now be 'awaiting_payment'):
--   private.auto_cancel_undispatched, private._cancel_before_collection,
--   public.admin_force_cancel, public.raise_dispute, private.detect_escrow_anomalies.
-- Existing rows: the 8 production orders are historical test records and are NOT
-- migrated or altered by this draft.

-- -----------------------------------------------------------------------------
-- 10. Intent creation (buyer, own order only)
-- -----------------------------------------------------------------------------
create function pay.create_payment_intent(p_order_id bigint)
returns table (reference text, amount_cents bigint, currency text)
language plpgsql security definer set search_path = pay, public as $$
declare v_buyer uuid := auth.uid(); v_total numeric; v_ref text; v_cents bigint;
begin
  if v_buyer is null then raise exception 'Not authenticated'; end if;
  if coalesce((select value from public.app_config where key = 'payments_live'), 'false') <> 'true' then
    raise exception 'Payments are not available';
  end if;
  select total_amount into v_total from public.orders
   where id = p_order_id and buyer_id = v_buyer
     and escrow_status = 'awaiting_payment' and status = 'pending' and not is_test_order
   for update;
  if not found then raise exception 'Order not found, not yours, or not awaiting payment'; end if;

  v_cents := round(v_total * 100)::bigint;
  if v_cents <= 0 or v_cents <> v_total * 100 then
    raise exception 'Order total is not a whole number of cents';
  end if;

  v_ref := 'MOP-' || p_order_id || '-' || encode(gen_random_bytes(12), 'hex');
  -- the partial unique index refuses a second live intent for the same order
  insert into pay.payment_intents (order_id, buyer_id, reference, amount_cents, currency)
  values (p_order_id, v_buyer, v_ref, v_cents, 'ZAR');
  return query select v_ref, v_cents, 'ZAR'::text;
end $$;
revoke all on function pay.create_payment_intent(bigint) from public;
-- Exposure to buyers goes through a thin public wrapper so schema pay stays unexposed:
--   public.start_payment(p_order_id bigint)  SECURITY DEFINER, grant to authenticated.

-- -----------------------------------------------------------------------------
-- 11. Event log writer and evidence writer (payment_writer only)
-- -----------------------------------------------------------------------------
create function pay.record_provider_event(
  p_event_id text, p_event_type text, p_reference text, p_body_sha256 text,
  p_signature_valid boolean, p_signing_key_id text, p_outcome text, p_detail text)
returns void language plpgsql security definer set search_path = pay, public as $$
begin
  if session_user <> 'payment_writer' then raise exception 'Not the payment writer'; end if;
  insert into pay.provider_events (provider, provider_event_id, event_type, reference, body_sha256,
                                   signature_valid, signing_key_id, outcome, detail)
  values ('paystack', p_event_id, p_event_type, p_reference, p_body_sha256,
          p_signature_valid, p_signing_key_id, p_outcome, left(p_detail, 500))
  on conflict (provider, provider_event_id) do nothing;      -- replay is a no-op
end $$;

create function pay.record_verified_payment(
  p_reference text, p_provider_transaction_id text, p_event_id text,
  p_amount_cents bigint, p_currency text, p_provider_status text, p_paid_at timestamptz,
  p_meta_order_id bigint, p_meta_buyer_id uuid,
  p_webhook_body_sha256 text, p_verify_response_sha256 text,
  p_signing_key_id text, p_verifier_build text)
returns bigint language plpgsql security definer set search_path = pay, public as $$
declare i pay.payment_intents; o record; v_evidence bigint;
begin
  if session_user <> 'payment_writer' then raise exception 'Not the payment writer'; end if;

  select * into i from pay.payment_intents where reference = p_reference for update;
  if not found then raise exception 'Unknown payment reference'; end if;

  -- idempotent: the same transaction delivered again returns the existing evidence
  select id into v_evidence from pay.payment_evidence
   where intent_id = i.id and provider_transaction_id = p_provider_transaction_id;
  if found then return v_evidence; end if;

  if i.status <> 'open' then raise exception 'Intent % is %, not open', i.id, i.status; end if;
  if p_provider_status <> 'success' then raise exception 'Provider status is not success'; end if;
  if p_amount_cents <> i.amount_cents then raise exception 'Amount does not match the intent'; end if;
  if p_currency <> i.currency then raise exception 'Currency does not match the intent'; end if;
  if p_meta_order_id is distinct from i.order_id then raise exception 'Provider metadata names a different order'; end if;
  if p_meta_buyer_id is distinct from i.buyer_id then raise exception 'Provider metadata names a different buyer'; end if;

  select id, buyer_id, total_amount, escrow_status, status, is_test_order into o
    from public.orders where id = i.order_id for update;
  if o.buyer_id <> i.buyer_id then raise exception 'Order buyer changed since the intent'; end if;
  if round(o.total_amount * 100)::bigint <> i.amount_cents then raise exception 'Order total changed since the intent'; end if;
  if o.escrow_status <> 'awaiting_payment' then raise exception 'Order % is %, not awaiting payment', o.id, o.escrow_status; end if;
  if o.is_test_order then raise exception 'Test orders cannot receive payment evidence'; end if;

  insert into pay.payment_evidence (intent_id, order_id, buyer_id, provider, provider_transaction_id,
        provider_reference, provider_event_id, amount_cents, currency, provider_status, provider_paid_at,
        webhook_body_sha256, verify_response_sha256, signing_key_id, verifier_build)
  values (i.id, i.order_id, i.buyer_id, 'paystack', p_provider_transaction_id,
        p_reference, p_event_id, p_amount_cents, p_currency, p_provider_status, p_paid_at,
        p_webhook_body_sha256, p_verify_response_sha256, p_signing_key_id, p_verifier_build)
  returning id into v_evidence;

  insert into pay.evidence_events (evidence_id, event, amount_cents, provider_ref)
  values (v_evidence, 'verified', p_amount_cents, p_reference);

  update pay.payment_intents set status = 'verified', closed_at = now() where id = i.id;

  -- same transaction: the only place an order can enter holding
  update public.orders set escrow_status = 'holding', status = 'paid', updated_at = now()
   where id = i.order_id;

  insert into public.admin_audit_log (admin_id, action, target_table, target_id, after_data)
  values (null, 'payment_evidence_recorded', 'orders', i.order_id::text,
          jsonb_build_object('evidence_id', v_evidence, 'amount_cents', p_amount_cents));
  return v_evidence;
end $$;

revoke all on function pay.record_provider_event(text,text,text,text,boolean,text,text,text) from public;
revoke all on function pay.record_verified_payment(text,text,text,bigint,text,text,timestamptz,bigint,uuid,text,text,text,text) from public;
grant execute on function pay.record_provider_event(text,text,text,text,boolean,text,text,text) to payment_writer;
grant execute on function pay.record_verified_payment(text,text,text,bigint,text,text,timestamptz,bigint,uuid,text,text,text,text) to payment_writer;

-- -----------------------------------------------------------------------------
-- 12. The guard (D4). Called first by every credit writer.
-- -----------------------------------------------------------------------------
create function pay.assert_release_allowed(p_order_id bigint)
returns bigint language plpgsql security definer set search_path = pay, public as $$
declare o record; e pay.payment_evidence; v_driver bigint;
begin
  if coalesce((select value from public.app_config where key = 'payments_live'), 'false') <> 'true' then
    raise exception 'Release refused: payments are not live (order %)', p_order_id;
  end if;

  select id, total_amount, escrow_status, is_test_order, route_id into o
    from public.orders where id = p_order_id for update;
  if not found then raise exception 'Release refused: order % not found', p_order_id; end if;
  if o.is_test_order then raise exception 'Release refused: order % is a test order', p_order_id; end if;
  if o.route_id is null then raise exception 'Release refused: order % is not a route order', p_order_id; end if;
  if o.escrow_status <> 'holding' then
    raise exception 'Release refused: order % escrow is %', p_order_id, o.escrow_status;
  end if;

  select * into e from pay.payment_evidence where order_id = p_order_id;
  if not found then raise exception 'Release refused: no verified payment evidence for order %', p_order_id; end if;
  if e.amount_cents <> round(o.total_amount * 100)::bigint or e.currency <> 'ZAR' then
    raise exception 'Release refused: evidence does not match order % total', p_order_id;
  end if;
  if exists (select 1 from pay.evidence_events x
              where x.evidence_id = e.id and x.event in ('refunded','refund_partial','charged_back')) then
    raise exception 'Release refused: payment for order % was refunded or charged back', p_order_id;
  end if;

  if exists (select 1 from public.disputes d
              where d.order_id = p_order_id and d.status in ('open','under_review','escalated')) then
    raise exception 'Release refused: open dispute on order %', p_order_id;
  end if;

  select driver_id into v_driver from public.deliveries where order_id = p_order_id limit 1;
  if v_driver is null then raise exception 'Release refused: order % has no driver', p_order_id; end if;

  if exists (select 1 from pay.allocation_legs l where l.order_id = p_order_id) then
    raise exception 'Release refused: order % is already allocated', p_order_id;
  end if;

  return e.id;
end $$;
revoke all on function pay.assert_release_allowed(bigint) from public;

-- -----------------------------------------------------------------------------
-- 13. Leaf functions
-- -----------------------------------------------------------------------------
-- 13a. Legacy leaf: disabled. Its split was never approved and it hands
--      unassigned legs to the seller.
create or replace function public._apply_order_payout_legacy(p_order_id bigint)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  raise exception 'Legacy payout is disabled (order %). Only guarded route orders can be released.', p_order_id;
end $$;

-- 13b. Route leaf: guard first, one allocation leg per recipient, suspense for a
--      missing marshal, every wallet write checked for exactly one row.
--      Split unchanged from the current function: platform 10% of product subtotal,
--      seller the rest of the subtotal, driver and marshal shares from the order
--      row, association share out of the platform's 10%, card fee to reserve.
create or replace function public._apply_route_payout(p_order_id bigint)
returns void language plpgsql security definer set search_path to 'public', 'pay' as $$
declare
  v_evidence bigint; o record; v_driver bigint; v_marshal bigint; v_rank bigint;
  c_total bigint; c_subtotal bigint; c_platform bigint; c_seller bigint;
  c_driver bigint; c_marshal bigint; c_card bigint; c_assoc bigint := 0;
  v_partner bigint; v_pct numeric; v_toll numeric; v_driver_partner bigint;
  v_wallet uuid; v_leg bigint; n int;
begin
  v_evidence := pay.assert_release_allowed(p_order_id);        -- FIRST STATEMENT

  select * into o from orders where id = p_order_id for update;
  select driver_id, marshal_id, origin_rank_id into v_driver, v_marshal, v_rank
    from deliveries where order_id = p_order_id limit 1;

  c_total    := round(o.total_amount * 100);
  c_subtotal := round(o.product_subtotal * 100);
  c_driver   := round(o.driver_delivery_share * 100);
  c_marshal  := round(o.marshal_delivery_share * 100);
  c_card     := round(o.card_processing_fee * 100);
  c_platform := round(o.product_subtotal * 10);                 -- 10% of subtotal, in cents
  c_seller   := c_subtotal - c_platform;

  if c_subtotal + round(o.delivery_fee * 100) + c_card <> c_total
     or c_driver + c_marshal <> round(o.delivery_fee * 100) then
    raise exception 'Order % totals do not reconcile', p_order_id;
  end if;

  if v_rank is not null then
    select taxi_partner_id into v_partner from taxi_ranks where id = v_rank;
    if v_partner is not null then
      select coalesce(revenue_share_pct,0), coalesce(non_member_toll_pct,0) into v_pct, v_toll
        from taxi_partners where id = v_partner;
      select taxi_partner_id into v_driver_partner from driver_profiles where id = v_driver;
      if v_driver_partner is distinct from v_partner then v_pct := v_pct + v_toll; end if;
      c_assoc := round(c_platform * v_pct / 100.0);
    end if;
  end if;

  if c_seller + (c_platform - c_assoc) + c_assoc + c_driver + c_marshal + c_card <> c_total then
    raise exception 'Order % allocation does not equal the buyer total', p_order_id;
  end if;

  -- ---- legs: one row each, always, including zero-value legs ------------------
  insert into pay.allocation_legs (order_id, evidence_id, leg, recipient_kind, recipient_ref, amount_cents, reason) values
    (p_order_id, v_evidence, 'seller',      'seller',      o.seller_id::text, c_seller, null),
    (p_order_id, v_evidence, 'platform',    'platform',    null,              c_platform - c_assoc, null),
    (p_order_id, v_evidence, 'driver',      'driver',      v_driver::text,    c_driver, null),
    (p_order_id, v_evidence, 'marshal',
       case when v_marshal is null then 'suspense' else 'marshal' end,
       v_marshal::text, c_marshal,
       case when v_marshal is null then 'no marshal assigned at release' end),
    (p_order_id, v_evidence, 'association', 'association', v_partner::text,   c_assoc,
       case when c_assoc = 0 then 'no association share applies' end),
    (p_order_id, v_evidence, 'card_fee',    'reserve',     null,              c_card,
       case when c_card = 0 then 'no card fee' end);

  insert into pay.allocation_events (leg_id, state, detail)
  select l.id,
         case when l.amount_cents = 0 then 'not_applicable'
              when l.recipient_kind = 'suspense' then 'pending_recipient'
              else 'released_internal' end,
         l.reason
    from pay.allocation_legs l where l.order_id = p_order_id;

  -- ---- wallet writes: each must change exactly one row ------------------------
  insert into seller_wallets (seller_id, available_balance, pending_balance, total_earned)
  values (o.seller_id, 0, 0, 0) on conflict (seller_id) do nothing;
  update seller_wallets set available_balance = available_balance + c_seller / 100.0,
                            total_earned = total_earned + c_seller / 100.0
   where seller_id = o.seller_id returning id into v_wallet;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Seller wallet write changed % rows', n; end if;
  insert into wallet_transactions (seller_id, wallet_id, type, amount, reference, transaction_category)
  values (o.seller_id, v_wallet, 'credit', c_seller / 100.0, 'Order #'||p_order_id||' product payout', 'seller');

  insert into driver_wallets (driver_id, available_balance, total_earned)
  values (v_driver, 0, 0) on conflict (driver_id) do nothing;
  update driver_wallets set available_balance = available_balance + c_driver / 100.0,
                            total_earned = total_earned + c_driver / 100.0
   where driver_id = v_driver;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Driver wallet write changed % rows', n; end if;
  if c_driver > 0 then
    insert into driver_marshal_transactions (order_id, recipient_type, recipient_id, amount, floor_applied)
    values (p_order_id, 'driver', v_driver, c_driver / 100.0, false);
  end if;

  if c_marshal > 0 and v_marshal is not null then
    insert into marshal_wallet (marshal_id, balance) values (v_marshal, 0) on conflict (marshal_id) do nothing;
    update marshal_wallet set balance = balance + c_marshal / 100.0 where marshal_id = v_marshal;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'Marshal wallet write changed % rows', n; end if;
    insert into driver_marshal_transactions (order_id, recipient_type, recipient_id, amount, floor_applied)
    values (p_order_id, 'marshal', v_marshal, c_marshal / 100.0, false);
  elsif c_marshal > 0 then
    -- explicit suspense: not the seller, not the platform, not the pooled marshal wallet
    update pay.suspense_balance set balance_cents = balance_cents + c_marshal where id = 1;
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'Suspense write changed % rows', n; end if;
  end if;

  if c_assoc > 0 then
    insert into association_earnings (taxi_partner_id, order_id, amount)
    values (v_partner, p_order_id, c_assoc / 100.0);
  end if;

  insert into platform_revenue (order_id, amount) values (p_order_id, (c_platform - c_assoc) / 100.0);
  update platform_wallet set balance = balance + (c_platform - c_assoc) / 100.0,
                             total_earned = total_earned + (c_platform - c_assoc) / 100.0,
                             processing_reserve = processing_reserve + c_card / 100.0
   where id = 1;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Platform wallet write changed % rows', n; end if;

  update orders set escrow_status = 'released', status = 'completed', updated_at = now() where id = p_order_id;

  insert into admin_audit_log (admin_id, action, target_table, target_id, after_data)
  values (null, 'order_released_internal', 'orders', p_order_id::text,
          jsonb_build_object('evidence_id', v_evidence, 'total_cents', c_total));
end $$;

-- 13c. Parent: guard is inside the leaf; the parent keeps the dispute rule and
--      refuses non-route orders before reaching the disabled legacy leaf.
create or replace function public._apply_order_payout(p_order_id bigint)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._apply_route_payout(p_order_id);
end $$;

-- -----------------------------------------------------------------------------
-- 14. Entry points (D4): owner only until each is rebuilt on the guarded path
-- -----------------------------------------------------------------------------
revoke execute on function public._apply_order_payout(bigint)                         from public, anon, authenticated, service_role;
revoke execute on function public._apply_order_payout_legacy(bigint)                  from public, anon, authenticated, service_role;
revoke execute on function public._apply_route_payout(bigint)                         from public, anon, authenticated, service_role;
revoke execute on function public.confirm_delivery(bigint, text)                      from public, anon, authenticated, service_role;
revoke execute on function public.confirm_order_delivery_by_phone(text, bigint, text) from public, anon, authenticated, service_role;
revoke execute on function public.complete_order(bigint, text)                        from public, anon, authenticated, service_role;
revoke execute on function public.resolve_dispute(bigint, text, text, text)           from public, anon, authenticated, service_role;
revoke execute on function public.admin_resolve_dispute(bigint, text, text, text)     from public, anon, authenticated, service_role;
revoke execute on function public.refund_order(bigint, text)                          from public, anon, authenticated, service_role;
drop function public.auto_release_escrow();        -- service-role wrapper; the cron calls the private function

-- NOT WRITTEN IN THIS DRAFT (design in the architecture document, sections 6 to 8):
--   * receipt recording (confirm_delivery replacement) and the single-use token table
--   * dispute resolution with an in-body admin check and an escalated path
--   * refund and chargeback application: reversal legs copied from recorded legs,
--     largest-remainder split for partial refunds, needs_recovery state
--   * external settlement submission with idempotency keys
--   * suspense assignment by an approved admin action
--   * reconciliation job and corrected integrity views
--   * removal of unused table privileges from authenticated (SEC-39)
--   * dispute insert policy with order ownership (SEC-43)

-- -----------------------------------------------------------------------------
-- 15. Self-check: fail the migration if any app or service role can write
-- -----------------------------------------------------------------------------
do $$
declare bad text;
begin
  select string_agg(c.relname || ':' || r, ', ') into bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace,
         unnest(array['anon','authenticated','service_role','payment_writer']) r
   where n.nspname = 'pay' and c.relkind = 'r'
     and (has_table_privilege(r, c.oid, 'INSERT') or has_table_privilege(r, c.oid, 'UPDATE')
          or has_table_privilege(r, c.oid, 'DELETE') or has_table_privilege(r, c.oid, 'TRUNCATE'));
  if bad is not null then raise exception 'Write privilege on pay tables: %', bad; end if;

  select string_agg(p.oid::regprocedure::text, ', ') into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('_apply_order_payout','_apply_order_payout_legacy','_apply_route_payout')
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
          or has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('service_role', p.oid, 'EXECUTE'));
  if bad is not null then raise exception 'Payout function still executable by an app or service role: %', bad; end if;
end $$;

-- A draft never commits.
rollback;
