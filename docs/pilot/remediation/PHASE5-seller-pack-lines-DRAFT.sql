-- PHASE 5 DRAFT: address-free seller packing view.
-- STATUS: NOT APPLIED. Staging only. Requires owner approval of the exact SQL before any apply.
-- Dry run on staging (rolled back) passed: seller 1 sees 4 distinct orders / 5 lines.
-- CAVEAT: column names (order_items.quantity, orders.created_at, products.name) must be
-- re-checked against the staging schema before this is approved. Not yet verified in this file.
--
-- Exposes: order id, product id, product name, quantity, order status, order time.
-- Does NOT expose: buyer id, buyer name, phone, delivery_address, driver or marshal ids, photos.

create or replace function public.seller_pack_lines()
returns table (
  order_id bigint,
  product_id bigint,
  product_name text,
  quantity integer,
  order_status text,
  ordered_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select o.id, oi.product_id, p.name, oi.quantity, o.status, o.created_at
    from order_items oi
    join orders o on o.id = oi.order_id
    join products p on p.id = oi.product_id
   where p.seller_id = auth.uid()
     and o.status <> 'cancelled'
$$;

revoke all on function public.seller_pack_lines() from public, anon;
grant execute on function public.seller_pack_lines() to authenticated;

-- Verification to run after apply (staging only), each must hold:
--   1. A seller calling seller_pack_lines() sees only their own product lines.
--   2. The result contains no buyer or address columns (shape check).
--   3. anon has no EXECUTE on the function.
-- Rollback: drop function public.seller_pack_lines();
