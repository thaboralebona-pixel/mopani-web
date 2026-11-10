-- SEC-06 PRODUCTION POLICY MIGRATION. DRAFT. NOT EXECUTED. NOT APPROVED.
-- Target: production (ProjectX, jpjjdzlhthvookllydai) ONLY after separate written owner approval.
-- Precondition 1: run and pass the staging test in PHASE4-SEC-06-STAGING-TEST.md on mopani-staging.
-- Precondition 2: capture the production policy list and grants immediately before running (rollback baseline).
-- Precondition 3: owner confirms the impact table in PRODUCTION-STAGING-DIFFERENCES.md, including the sellers' loss of order-level visibility.

begin;

-- 1. Products: anonymous and signed-in users see only listed products. Sellers read their own (including unlisted) products.
drop policy if exists "public can read" on public.products;
create policy "public can read listed products" on public.products for select to anon, authenticated using (is_available = true);
create policy "sellers read own products" on public.products for select to authenticated using (auth.uid() = seller_id);

-- 2. Orders: sellers no longer read full order rows (buyer delivery address, buyer id, payment references).
drop policy if exists "Seller can view their product orders" on public.orders;
drop policy if exists "seller view own sales" on public.orders;

-- 3. Deliveries: buyers and sellers no longer read driver and marshal identifiers or proof photos directly.
drop policy if exists deliveries_participant_read on public.deliveries;

-- 4. Replacement read paths (exact definitions as tested on staging).
create or replace function public.seller_sales()
returns table(order_id bigint, created_at timestamptz, status text, product_subtotal numeric, seller_earnings numeric, destination text)
language sql stable security definer set search_path = public
as $function$ select distinct o.id, o.created_at, o.status, o.product_subtotal, o.seller_earnings, o.destination from public.orders o join public.order_items oi on oi.order_id = o.id join public.products p on p.id = oi.product_id where p.seller_id = auth.uid() $function$;

create or replace function public.buyer_delivery(p_order_id bigint)
returns table(delivery_status text, collected_at timestamptz, in_transit_at timestamptz, delivered_at timestamptz, proof_of_delivery_url text)
language sql stable security definer set search_path = public
as $function$ select d.status, d.collected_at, d.in_transit_at, d.delivered_at, d.proof_of_delivery_url from public.deliveries d join public.orders o on o.id = d.order_id where d.order_id = p_order_id and o.buyer_id = auth.uid() $function$;

revoke execute on function public.seller_sales() from public, anon;
grant execute on function public.seller_sales() to authenticated;
revoke execute on function public.buyer_delivery(bigint) from public, anon;
grant execute on function public.buyer_delivery(bigint) to authenticated;

-- 5. Verification (must return the expected values before COMMIT).
do $$
begin
  if exists (select 1 from pg_policies where schemaname='public' and tablename='products' and policyname='public can read') then raise exception 'products old policy still present'; end if;
  if exists (select 1 from pg_policies where schemaname='public' and tablename='orders' and policyname in ('Seller can view their product orders','seller view own sales')) then raise exception 'seller order policy still present'; end if;
  if exists (select 1 from pg_policies where schemaname='public' and tablename='deliveries' and policyname='deliveries_participant_read') then raise exception 'delivery participant policy still present'; end if;
end $$;

commit;

-- ROLLBACK (only if a production problem is confirmed and the owner approves). Recreate the captured production definitions:
-- begin;
-- drop policy if exists "public can read listed products" on public.products;
-- drop policy if exists "sellers read own products" on public.products;
-- create policy "public can read" on public.products for select to public using (true);
-- create policy "Seller can view their product orders" on public.orders for select to public using (exists (select 1 from (order_items oi join products p on (p.id = oi.product_id)) where ((oi.order_id = orders.id) and (p.seller_id = auth.uid()))));
-- create policy "seller view own sales" on public.orders for select to public using (seller_id = auth.uid());
-- create policy deliveries_participant_read on public.deliveries for select to public using (exists (select 1 from orders o where ((o.id = deliveries.order_id) and ((o.buyer_id = auth.uid()) or (o.seller_id = auth.uid())))));
-- commit;
