import type { SupabaseClient } from '@supabase/supabase-js';
import { toCents, type Cents } from '../domain/money';

export interface Product {
  readonly id: number;
  readonly sellerId: string;
  readonly name: string;
  readonly unitPriceCents: Cents;
  readonly unit: string;
  readonly stock: number;
  readonly district: string | null;
  readonly category: string | null;
  /** Average weight of one unit in kg, or null when none is recorded. A null weight is counted as 5 kg for delivery. */
  readonly weightKg: number | null;
}

export interface Route {
  readonly origin: string;
  readonly destination: string;
  readonly minProductCents: Cents;
  readonly deliveryFeeCents: Cents;
}

export interface ProductFilter {
  readonly district?: string;
  readonly category?: string;
}

const PRODUCT_COLUMNS =
  'id, seller_id, name, price, unit_of_measure, stock_quantity, district, category, avg_unit_weight_kg';

/** Returns a positive finite number, or null for anything else (including zero and missing values). */
function positiveNumber(v: unknown): number | null {
  const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
  return typeof n === 'number' && Number.isFinite(n) && n > 0 ? n : null;
}

function nonEmptyString(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : null;
}

/** Keeps only rows that pass every check. Anything malformed is counted as dropped, never shown. */
export function parseProducts(rows: unknown): { products: Product[]; dropped: number } {
  if (!Array.isArray(rows)) return { products: [], dropped: 0 };
  const products: Product[] = [];
  let dropped = 0;
  for (const row of rows) {
    const r = (typeof row === 'object' && row !== null ? row : {}) as Record<string, unknown>;
    const id = r['id'];
    const sellerId = nonEmptyString(r['seller_id']);
    const name = nonEmptyString(r['name']);
    const unit = nonEmptyString(r['unit_of_measure']);
    const price = toCents(r['price']);
    const stock = r['stock_quantity'];
    const valid =
      typeof id === 'number' &&
      Number.isInteger(id) &&
      id > 0 &&
      sellerId !== null &&
      name !== null &&
      unit !== null &&
      price !== null &&
      price > 0 &&
      typeof stock === 'number' &&
      Number.isInteger(stock) &&
      stock >= 0;
    if (!valid) {
      dropped += 1;
      continue;
    }
    products.push({
      id: id as number,
      sellerId: sellerId as string,
      name: name as string,
      unitPriceCents: price as Cents,
      unit: unit as string,
      stock: stock as number,
      district: nonEmptyString(r['district']),
      category: nonEmptyString(r['category']),
      weightKg: positiveNumber(r['avg_unit_weight_kg']),
    });
  }
  return { products, dropped };
}

export function parseRoutes(rows: unknown): Route[] {
  if (!Array.isArray(rows)) return [];
  const routes: Route[] = [];
  for (const row of rows) {
    const r = (typeof row === 'object' && row !== null ? row : {}) as Record<string, unknown>;
    const origin = nonEmptyString(r['origin_district']);
    const destination = nonEmptyString(r['destination']);
    const minProduct = toCents(r['min_product_value']);
    const fee = toCents(r['total_fee']);
    if (origin && destination && minProduct !== null && fee !== null) {
      routes.push({ origin, destination, minProductCents: minProduct, deliveryFeeCents: fee });
    }
  }
  return routes;
}

export function filterProducts(products: readonly Product[], filter: ProductFilter): Product[] {
  return products.filter(
    (p) =>
      (filter.district === undefined || p.district === filter.district) &&
      (filter.category === undefined || p.category === filter.category)
  );
}

export type FetchResult<T> = { readonly ok: true; readonly value: T } | { readonly ok: false };

/** Reads listed products (is_available = true). Read access depends on row-level security; a failure is reported as ok: false. */
export async function fetchProducts(
  client: SupabaseClient
): Promise<FetchResult<{ products: Product[]; dropped: number }>> {
  const { data, error } = await client
    .from('products')
    .select(PRODUCT_COLUMNS)
    .eq('is_available', true);
  if (error) return { ok: false };
  return { ok: true, value: parseProducts(data) };
}

/** Reads active delivery routes, so the minimum basket and delivery fee can be shown before the buyer asks for a total. */
export async function fetchRoutes(client: SupabaseClient): Promise<FetchResult<Route[]>> {
  const { data, error } = await client
    .from('delivery_routes')
    .select('origin_district, destination, min_product_value, total_fee')
    .eq('active', true);
  if (error) return { ok: false };
  return { ok: true, value: parseRoutes(data) };
}
