import { formatRand, type Cents } from '../domain/money';
import { deliveryShareOfGoodsPct, type Quote } from '../domain/quote';
import type { BasketLine } from '../domain/basket';
import { subtotalCents } from '../domain/basket';
import type { Product, Route } from '../data/catalog';
import { strings2 as s } from '../strings/en';

export interface Handlers {
  onAdd(productId: number): void;
  onIncrease(productId: number): void;
  onDecrease(productId: number): void;
  onRemove(productId: number): void;
  onGetTotal(): void;
}

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
  text?: string
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(label: string, onClick: () => void, className = 'btn'): HTMLButtonElement {
  const b = el('button', className, label);
  b.type = 'button';
  b.addEventListener('click', onClick);
  return b;
}

function section(heading: string, body: HTMLElement[]): HTMLElement {
  const wrap = el('section', 'card');
  wrap.append(el('h2', undefined, heading), ...body);
  return wrap;
}

export function catalogSection(
  products: readonly Product[],
  dropped: number,
  h: Handlers
): HTMLElement {
  const nodes: HTMLElement[] = [];
  if (products.length === 0) {
    nodes.push(el('p', 'notice', s.catalogEmpty));
  }
  const list = el('ul', 'list');
  for (const p of products) {
    const item = el('li', 'product');
    item.append(
      el('p', 'product-name', p.name),
      el('p', 'meta', `${formatRand(p.unitPriceCents)} per ${p.unit}`),
      el('p', 'meta', `${s.stockLabel}: ${p.stock}${p.district ? ` · ${p.district}` : ''}`),
      button(s.addToBasket, () => h.onAdd(p.id), 'btn btn-primary')
    );
    list.append(item);
  }
  if (products.length > 0) nodes.push(list);
  if (dropped > 0) nodes.push(el('p', 'notice notice-warning', s.catalogDropped));
  return section(s.catalogHeading, nodes);
}

export function routesSection(routes: readonly Route[] | null): HTMLElement {
  if (routes === null)
    return section(s.routesHeading, [el('p', 'notice notice-warning', s.routesLoadError)]);
  const list = el('ul', 'list');
  for (const r of routes) {
    list.append(
      el(
        'li',
        'route',
        `${r.origin} to ${r.destination}: ${s.routeMinimum} ${formatRand(r.minProductCents)}, ${s.routeFee} ${formatRand(r.deliveryFeeCents)}`
      )
    );
  }
  return section(s.routesHeading, [list]);
}

export function basketSection(
  lines: readonly BasketLine[],
  h: Handlers,
  canGetTotal: boolean
): HTMLElement {
  const body: HTMLElement[] = [];
  if (lines.length === 0) {
    body.push(el('p', 'notice', s.basketEmpty));
  } else {
    const list = el('ul', 'list');
    for (const l of lines) {
      const row = el('li', 'line');
      row.append(
        el('p', 'product-name', l.name),
        el('p', 'meta', `${l.quantity} × ${formatRand(l.unitPriceCents)}`),
        button(s.decrease, () => h.onDecrease(l.productId)),
        button(s.increase, () => h.onIncrease(l.productId)),
        button(s.remove, () => h.onRemove(l.productId), 'btn btn-quiet')
      );
      list.append(row);
    }
    body.push(
      list,
      el('p', 'subtotal', `${s.subtotalLabel}: ${formatRand(subtotalCents(lines))}`),
      el('p', 'meta', s.subtotalNote)
    );
    const getTotal = button(s.getTotal, h.onGetTotal, 'btn btn-primary');
    getTotal.disabled = !canGetTotal;
    body.push(getTotal);
  }
  return section(s.basketHeading, body);
}

export function quoteSection(quote: Quote): HTMLElement {
  const share = deliveryShareOfGoodsPct(quote.productSubtotalCents, quote.deliveryFeeCents);
  const rows: [string, Cents][] = [
    [s.quoteProduct, quote.productSubtotalCents],
    [s.quoteDelivery, quote.deliveryFeeCents],
    [s.quoteCard, quote.cardFeeCents],
    [s.quoteTotal, quote.totalCents],
  ];
  const body: HTMLElement[] = rows.map(([label, cents]) =>
    el('p', 'quote-row', `${label}: ${formatRand(cents)}`)
  );
  if (quote.weightKg !== null && quote.blocks !== null) {
    body.push(
      el(
        'p',
        'meta',
        s.quoteWeight
          .replace('{kg}', String(quote.weightKg))
          .replace('{blocks}', String(quote.blocks))
      )
    );
  }
  if (share !== null) body.push(el('p', 'meta', s.quoteShare.replace('{pct}', share.toFixed(1))));
  return section(s.quoteHeading, body);
}

// Read-only. No balances and no withdraw control until sign-in and the payment provider are live.
export function paymentsSection(): HTMLElement {
  return section(s.paymentsHeading, [
    el('p', 'meta', s.paymentsNotYet),
    el('p', 'meta', s.paymentsSignIn),
    el('p', 'meta', s.paymentsNoWithdraw),
  ]);
}

export function noticeSection(text: string, warning: boolean): HTMLElement {
  return el('p', warning ? 'notice notice-warning' : 'notice', text);
}
