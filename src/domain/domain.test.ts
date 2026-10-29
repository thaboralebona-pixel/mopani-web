import { describe, expect, it } from 'vitest';
import { formatRand, toCents } from './money';
import {
  addProduct,
  MAX_QUANTITY,
  setQuantity,
  subtotalCents,
  toQuoteItems,
  type BasketLine,
} from './basket';
import { deliveryShareOfGoodsPct, mapQuoteError, parseQuote } from './quote';

const apple = { id: 1, name: 'Mango', unitPriceCents: 1800, stock: 3 };
const appleLine = (quantity: number, stock = 3): BasketLine => ({
  productId: 1,
  name: 'Mango',
  unitPriceCents: 1800,
  stock,
  quantity,
});

describe('money', () => {
  it('converts decimal rand strings and numbers to integer cents', () => {
    expect(toCents('180.00')).toBe(18000);
    expect(toCents('12.5')).toBe(1250);
    expect(toCents(0.1 + 0.2)).toBe(30);
  });

  it('rejects malformed, negative and non-finite values', () => {
    expect(toCents('abc')).toBeNull();
    expect(toCents('1.234')).toBeNull();
    expect(toCents(-5)).toBeNull();
    expect(toCents(Number.NaN)).toBeNull();
    expect(toCents(null)).toBeNull();
  });

  it('formats cents for display', () => {
    expect(formatRand(18000)).toBe('R180.00');
    expect(formatRand(1205)).toBe('R12.05');
  });
});

describe('basket', () => {
  it('adds a product once and increments it on a second add', () => {
    const first = addProduct([], apple);
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    const second = addProduct(first.lines, apple);
    expect(second.ok && second.lines[0]?.quantity).toBe(2);
  });

  it('refuses to add beyond the stock shown', () => {
    const lines: BasketLine[] = [appleLine(3)];
    expect(addProduct(lines, apple)).toEqual({ ok: false, error: 'exceeds_stock' });
  });

  it('refuses an out-of-stock product', () => {
    expect(addProduct([], { ...apple, stock: 0 })).toEqual({ ok: false, error: 'out_of_stock' });
  });

  it('enforces the 1 to 50 quantity range', () => {
    const lines: BasketLine[] = [appleLine(1, 500)];
    expect(setQuantity(lines, 1, 0)).toEqual({ ok: false, error: 'quantity_out_of_range' });
    expect(setQuantity(lines, 1, MAX_QUANTITY + 1)).toEqual({
      ok: false,
      error: 'quantity_out_of_range',
    });
    expect(setQuantity(lines, 1, 1.5)).toEqual({ ok: false, error: 'quantity_out_of_range' });
  });

  it('computes the display subtotal and quote items', () => {
    const lines: BasketLine[] = [
      appleLine(2),
      { productId: 2, name: 'Atchar', unitPriceCents: 5000, stock: 9, quantity: 1 },
    ];
    expect(subtotalCents(lines)).toBe(8600);
    expect(toQuoteItems(lines)).toEqual([
      { product_id: 1, quantity: 2 },
      { product_id: 2, quantity: 1 },
    ]);
  });
});

describe('quote parsing', () => {
  const good = {
    product_subtotal: '180.00',
    delivery_fee: '160.00',
    card_processing_fee: 0,
    total: '340.00',
    seller_id: 'synthetic-seller-a',
    destination: 'Johannesburg',
  };

  it('accepts a consistent quote', () => {
    const q = parseQuote(good);
    expect(q?.totalCents).toBe(34000);
    expect(q?.deliveryFeeCents).toBe(16000);
  });

  it('refuses a quote whose total does not equal its parts', () => {
    expect(parseQuote({ ...good, total: '341.00' })).toBeNull();
  });

  it('refuses a missing or malformed field', () => {
    expect(parseQuote({ ...good, seller_id: '' })).toBeNull();
    expect(parseQuote({ ...good, delivery_fee: 'free' })).toBeNull();
    expect(parseQuote(null)).toBeNull();
  });

  it('shows delivery as a share of product value', () => {
    expect(deliveryShareOfGoodsPct(18000, 16000)).toBe(88.9);
    expect(deliveryShareOfGoodsPct(0, 16000)).toBeNull();
  });
});

describe('server error mapping', () => {
  it('maps known server messages to fixed keys', () => {
    expect(mapQuoteError('Please sign in to order')).toBe('needs_sign_in');
    expect(mapQuoteError('Minimum order value for delivery to X is R180. Add more items')).toBe(
      'below_minimum'
    );
    expect(mapQuoteError('No delivery route is set up for this destination yet.')).toBe('no_route');
    expect(
      mapQuoteError('One of the items is unavailable or has less stock than you asked for.')
    ).toBe('stock_changed');
    expect(mapQuoteError('Quantities must be between 1 and 50')).toBe('quantity');
  });

  it('maps anything unknown to the generic message, never the raw text', () => {
    expect(mapQuoteError('relation "secret_table" does not exist')).toBe('generic');
  });
});
