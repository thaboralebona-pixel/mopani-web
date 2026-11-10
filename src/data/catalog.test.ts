import { describe, expect, it } from 'vitest';
import { filterProducts, parseProducts, parseRoutes } from './catalog';

const row = (over: Record<string, unknown> = {}) => ({
  id: 10,
  seller_id: 'synthetic-seller-a',
  name: 'Mango',
  price: '18.00',
  unit_of_measure: 'kg',
  stock_quantity: 5,
  district: 'Elim',
  category: 'fruit',
  ...over,
});

describe('parseProducts', () => {
  it('keeps complete rows and converts prices to cents', () => {
    const { products, dropped } = parseProducts([row()]);
    expect(dropped).toBe(0);
    expect(products[0]?.unitPriceCents).toBe(1800);
  });

  it('drops malformed rows and counts them, never shows them', () => {
    const { products, dropped } = parseProducts([
      row(),
      row({ id: 'x' }),
      row({ price: '-1' }),
      row({ price: '0' }),
      row({ stock_quantity: -2 }),
      row({ name: '  ' }),
      null,
    ]);
    expect(products).toHaveLength(1);
    expect(dropped).toBe(6);
  });

  it('carries the recorded unit weight, and leaves it null when missing or zero', () => {
    const { products } = parseProducts([
      row({ avg_unit_weight_kg: '0.500' }),
      row({ id: 11, avg_unit_weight_kg: null }),
      row({ id: 12, avg_unit_weight_kg: '0' }),
      row({ id: 13 }),
    ]);
    expect(products.map((p) => p.weightKg)).toEqual([0.5, null, null, null]);
  });

  it('returns nothing for a non-array response', () => {
    expect(parseProducts({ not: 'an array' })).toEqual({ products: [], dropped: 0 });
  });
});

describe('parseRoutes', () => {
  it('keeps routes with valid minimum and fee values', () => {
    const routes = parseRoutes([
      {
        origin_district: 'Elim',
        destination: 'Johannesburg',
        min_product_value: '180.00',
        total_fee: '160.00',
      },
      {
        origin_district: 'Elim',
        destination: 'Johannesburg',
        min_product_value: 'lots',
        total_fee: '160.00',
      },
    ]);
    expect(routes).toHaveLength(1);
    expect(routes[0]?.minProductCents).toBe(18000);
  });
});

describe('filterProducts', () => {
  const products = parseProducts([
    row(),
    row({ id: 11, district: 'Thohoyandou', category: 'vegetables' }),
  ]).products;

  it('filters by town and by category', () => {
    expect(filterProducts(products, { district: 'Elim' })).toHaveLength(1);
    expect(filterProducts(products, { category: 'vegetables' })).toHaveLength(1);
    expect(filterProducts(products, {})).toHaveLength(2);
  });
});
