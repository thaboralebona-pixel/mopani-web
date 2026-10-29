import type { Cents } from './money';

export const MIN_QUANTITY = 1;
export const MAX_QUANTITY = 50;

export interface BasketLine {
  readonly productId: number;
  readonly name: string;
  readonly unitPriceCents: Cents;
  readonly stock: number;
  readonly quantity: number;
}

export type BasketError =
  | 'quantity_out_of_range'
  | 'exceeds_stock'
  | 'not_in_basket'
  | 'out_of_stock';
export type BasketResult =
  | { readonly ok: true; readonly lines: BasketLine[] }
  | { readonly ok: false; readonly error: BasketError };

export interface ProductRef {
  readonly id: number;
  readonly name: string;
  readonly unitPriceCents: Cents;
  readonly stock: number;
}

function checkQuantity(quantity: number, stock: number): BasketError | null {
  if (!Number.isInteger(quantity) || quantity < MIN_QUANTITY || quantity > MAX_QUANTITY)
    return 'quantity_out_of_range';
  if (quantity > stock) return 'exceeds_stock';
  return null;
}

/** Adds one unit of a product. Client checks are an early warning only; the server re-checks stock and quantity. */
export function addProduct(lines: readonly BasketLine[], product: ProductRef): BasketResult {
  if (product.stock < MIN_QUANTITY) return { ok: false, error: 'out_of_stock' };
  const existing = lines.find((l) => l.productId === product.id);
  if (!existing) {
    return {
      ok: true,
      lines: [
        ...lines,
        {
          productId: product.id,
          name: product.name,
          unitPriceCents: product.unitPriceCents,
          stock: product.stock,
          quantity: MIN_QUANTITY,
        },
      ],
    };
  }
  const next = existing.quantity + 1;
  const error = checkQuantity(next, product.stock);
  if (error) return { ok: false, error };
  return {
    ok: true,
    lines: lines.map((l) =>
      l.productId === product.id ? { ...l, stock: product.stock, quantity: next } : l
    ),
  };
}

export function setQuantity(
  lines: readonly BasketLine[],
  productId: number,
  quantity: number
): BasketResult {
  const line = lines.find((l) => l.productId === productId);
  if (!line) return { ok: false, error: 'not_in_basket' };
  const error = checkQuantity(quantity, line.stock);
  if (error) return { ok: false, error };
  return {
    ok: true,
    lines: lines.map((l) => (l.productId === productId ? { ...l, quantity } : l)),
  };
}

export function removeProduct(lines: readonly BasketLine[], productId: number): BasketLine[] {
  return lines.filter((l) => l.productId !== productId);
}

/** Product subtotal for display only. The total the buyer pays is always the server's quote. */
export function subtotalCents(lines: readonly BasketLine[]): Cents {
  return lines.reduce((sum, l) => sum + l.unitPriceCents * l.quantity, 0);
}

export function toQuoteItems(
  lines: readonly BasketLine[]
): { product_id: number; quantity: number }[] {
  return lines.map((l) => ({ product_id: l.productId, quantity: l.quantity }));
}
