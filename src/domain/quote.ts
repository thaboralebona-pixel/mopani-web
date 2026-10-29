import { toCents, type Cents } from './money';

export interface Quote {
  readonly productSubtotalCents: Cents;
  readonly deliveryFeeCents: Cents;
  readonly cardFeeCents: Cents;
  readonly totalCents: Cents;
  readonly sellerId: string;
  readonly destination: string;
}

/**
 * Parses the server's quote_order response. Returns null for any missing, malformed or inconsistent value,
 * so the UI never shows a total it cannot check. The total must equal the sum of its parts.
 */
export function parseQuote(raw: unknown): Quote | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const product = toCents(r['product_subtotal']);
  const delivery = toCents(r['delivery_fee']);
  const card = toCents(r['card_processing_fee']);
  const total = toCents(r['total']);
  const sellerId = r['seller_id'];
  const destination = r['destination'];
  if (product === null || delivery === null || card === null || total === null) return null;
  if (typeof sellerId !== 'string' || sellerId.trim() === '') return null;
  if (typeof destination !== 'string' || destination.trim() === '') return null;
  if (product + delivery + card !== total) return null;
  return {
    productSubtotalCents: product,
    deliveryFeeCents: delivery,
    cardFeeCents: card,
    totalCents: total,
    sellerId,
    destination,
  };
}

/** Delivery as a percentage of product value, to one decimal place. Null when product value is zero. */
export function deliveryShareOfGoodsPct(productCents: Cents, deliveryCents: Cents): number | null {
  if (productCents <= 0) return null;
  return Math.round((deliveryCents / productCents) * 1000) / 10;
}

export type QuoteErrorKey =
  | 'needs_sign_in'
  | 'below_minimum'
  | 'no_route'
  | 'stock_changed'
  | 'quantity'
  | 'local_town_only'
  | 'one_seller_only'
  | 'generic';

/** Maps server error text to a fixed, plain-language key. The server text is never shown to the user. */
export function mapQuoteError(serverMessage: string): QuoteErrorKey {
  const m = serverMessage.toLowerCase();
  if (m.includes('please sign in')) return 'needs_sign_in';
  if (m.includes('minimum order value')) return 'below_minimum';
  if (m.includes('no delivery route')) return 'no_route';
  if (m.includes('less stock') || m.includes('unavailable')) return 'stock_changed';
  if (m.includes('quantities must be between')) return 'quantity';
  if (m.includes('local delivery is only')) return 'local_town_only';
  if (m.includes('one seller')) return 'one_seller_only';
  return 'generic';
}
