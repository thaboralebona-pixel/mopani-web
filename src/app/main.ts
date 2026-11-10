import { validateConfig, type RawConfig } from '../config/environment';
import { environmentBanner } from '../lib/banner';
import { createAppClient } from '../lib/supabase';
import { strings, strings2 as s } from '../strings/en';
import {
  addProduct,
  removeProduct,
  setQuantity,
  toQuoteItems,
  type BasketError,
  type BasketLine,
} from '../domain/basket';
import { mapQuoteError, parseQuote, type Quote, type QuoteErrorKey } from '../domain/quote';
import { fetchProducts, fetchRoutes, type Product, type Route } from '../data/catalog';
import {
  basketSection,
  catalogSection,
  noticeSection,
  paymentsSection,
  quoteSection,
  routesSection,
  type Handlers,
} from '../ui/render';
import type { SupabaseClient } from '@supabase/supabase-js';

// Sign-in codes are not yet deliverable. quote_order requires a signed-in buyer, so totals stay off until this is true.
const SIGN_IN_ENABLED = false;
const PILOT_DESTINATION = 'Johannesburg';

interface State {
  products: Product[];
  dropped: number;
  productsLoaded: boolean;
  routes: Route[] | null;
  basket: BasketLine[];
  basketNotice: string | null;
  quote: Quote | null;
  quoteError: string | null;
  quoteLoading: boolean;
}

const state: State = {
  products: [],
  dropped: 0,
  productsLoaded: false,
  routes: null,
  basket: [],
  basketNotice: null,
  quote: null,
  quoteError: null,
  quoteLoading: false,
};

const basketErrorText: Record<BasketError, string> = {
  quantity_out_of_range: s.basketErrorQuantity,
  exceeds_stock: s.basketErrorStock,
  out_of_stock: s.basketErrorOutOfStock,
  not_in_basket: s.basketEmpty,
};

const quoteErrorText: Record<QuoteErrorKey, string> = {
  needs_sign_in: s.quoteNeedsSignIn,
  below_minimum: s.quoteBelowMinimum,
  no_route: s.quoteNoRoute,
  stock_changed: s.quoteStockChanged,
  quantity: s.quoteQuantity,
  local_town_only: s.quoteLocalTownOnly,
  one_seller_only: s.quoteOneSellerOnly,
  generic: s.quoteGeneric,
};

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  text?: string
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  return node;
}

let client: SupabaseClient | null = null;
let root: HTMLElement | null = null;

function productById(id: number): Product | undefined {
  return state.products.find((p) => p.id === id);
}

function applyBasket(result: ReturnType<typeof addProduct>): void {
  if (result.ok) {
    state.basket = result.lines;
    state.basketNotice = null;
  } else {
    state.basketNotice = basketErrorText[result.error];
  }
}

function invalidateQuote(): void {
  state.quote = null;
  state.quoteError = null;
}

const handlers: Handlers = {
  onAdd(productId) {
    const p = productById(productId);
    if (!p) return;
    applyBasket(
      addProduct(state.basket, {
        id: p.id,
        name: p.name,
        unitPriceCents: p.unitPriceCents,
        stock: p.stock,
      })
    );
    invalidateQuote();
    render();
  },
  onIncrease(productId) {
    const line = state.basket.find((l) => l.productId === productId);
    if (!line) return;
    applyBasket(setQuantity(state.basket, productId, line.quantity + 1));
    invalidateQuote();
    render();
  },
  onDecrease(productId) {
    const line = state.basket.find((l) => l.productId === productId);
    if (!line) return;
    if (line.quantity <= 1) {
      state.basket = removeProduct(state.basket, productId);
      state.basketNotice = null;
    } else {
      applyBasket(setQuantity(state.basket, productId, line.quantity - 1));
    }
    invalidateQuote();
    render();
  },
  onRemove(productId) {
    state.basket = removeProduct(state.basket, productId);
    state.basketNotice = null;
    invalidateQuote();
    render();
  },
  async onGetTotal() {
    // Ignore repeat taps while a quote is already on its way.
    if (state.quoteLoading) return;
    if (!SIGN_IN_ENABLED || !client) {
      state.quote = null;
      state.quoteError = s.quoteNeedsSignIn;
      render();
      return;
    }
    state.quoteLoading = true;
    state.quote = null;
    state.quoteError = null;
    render();
    try {
      // Calls the existing server function with the items and the pilot destination. The server sets every amount.
      const { data, error } = await client.rpc('quote_order', {
        p_items: toQuoteItems(state.basket),
        p_destination: PILOT_DESTINATION,
      });
      if (error) {
        const key: QuoteErrorKey = mapQuoteError(error.message ?? '');
        state.quote = null;
        state.quoteError = quoteErrorText[key];
      } else {
        const parsed = parseQuote(data);
        state.quote = parsed;
        state.quoteError = parsed ? null : s.quoteGeneric;
      }
    } catch {
      // Network failure: never show a total that was not confirmed by the server.
      state.quote = null;
      state.quoteError = s.quoteGeneric;
    } finally {
      state.quoteLoading = false;
      render();
    }
  },
};

function render(): void {
  if (!root) return;
  const nodes: HTMLElement[] = [];
  const banner = environmentBanner(currentEnv);
  if (banner.visible) {
    const b = el('div', banner.text);
    b.className = 'env-banner';
    b.setAttribute('role', 'status');
    nodes.push(b);
  }
  const heading = el('h1', strings.appName);
  const pilot = el('p', strings.pilotNotice);
  pilot.className = 'notice';
  nodes.push(heading, pilot);
  if (!SIGN_IN_ENABLED) nodes.push(noticeSection(strings.signInUnavailable, true));

  nodes.push(
    state.productsLoaded
      ? catalogSection(state.products, state.dropped, handlers)
      : noticeSection(s.catalogLoadError, true)
  );
  nodes.push(routesSection(state.routes));
  nodes.push(
    basketSection(
      state.basket,
      handlers,
      SIGN_IN_ENABLED && state.basket.length > 0,
      state.quoteLoading
    )
  );
  if (state.basketNotice) nodes.push(noticeSection(state.basketNotice, true));
  if (state.quote) nodes.push(quoteSection(state.quote));
  if (state.quoteError) nodes.push(noticeSection(state.quoteError, true));
  nodes.push(paymentsSection());
  root.replaceChildren(...nodes);
}

let currentEnv: 'local' | 'staging' | 'production' = 'local';

async function start(): Promise<void> {
  root = document.getElementById('app');
  if (!root) return;

  const raw = (window as unknown as { MOPANI_CONFIG?: RawConfig }).MOPANI_CONFIG;
  if (!raw) {
    root.replaceChildren(el('h1', strings.appName), el('p', strings.configMissing));
    return;
  }
  const result = validateConfig(raw);
  if (!result.ok) {
    root.replaceChildren(
      el('h1', strings.appName),
      el('p', `${strings.configInvalid} ${result.errors.join(' ')}`)
    );
    return;
  }
  currentEnv = result.config.env;
  client = createAppClient(result.config);

  const [productsResult, routesResult] = await Promise.all([
    fetchProducts(client),
    fetchRoutes(client),
  ]);
  if (productsResult.ok) {
    state.products = productsResult.value.products;
    state.dropped = productsResult.value.dropped;
    state.productsLoaded = true;
  }
  state.routes = routesResult.ok ? routesResult.value : null;
  render();

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => undefined);
  }
}

void start();
