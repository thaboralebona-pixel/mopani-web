# Increment 2: Browse and quote (buyer), pull request record

## Status

Built and tested in the increment-1 workspace copy. NOT yet merged. It is not verified against the repository at commit 46efe9c, and it has not been run in a browser. Read the "Not verified" list before relying on it.

## Scope

- Catalog of listed produce, with a basket (add, increase, decrease, remove). Quantities are limited to 1 to 50 and to the stock shown.
- Routes panel: minimum basket and delivery fee for each active route, read from delivery_routes.
- Subtotal shown for display only. The total is never calculated on the client.
- "Get my total" calls the existing quote_order function with p_items and p_destination = "Johannesburg". It is disabled while sign-in is off.
- Server error text is mapped to fixed plain-language messages, never shown raw.
- Delivery shown as a share of product value.

Not included: payments, checkout and order placement (Increment 3), sign-in, new server functions, new migrations.

## Files

Added: src/domain/money.ts, src/domain/basket.ts, src/domain/quote.ts, src/domain/domain.test.ts, src/data/catalog.ts, src/data/catalog.test.ts, src/ui/render.ts, src/strings/en.test.ts.
Changed: src/app/main.ts (screen wiring), src/strings/en.ts (added strings2 block), index.html (unchanged in content, reformatted).
Unchanged: config, guard, banner, Supabase client factory, service worker, tokens, build script.

## Commands and results (from the workspace copy)

- npm run check: exit 0. 5 test files, 46 tests passed. Full output in CHECK-OUTPUT-INCREMENT-2.txt.
- npm run build: exit 0, "build ok: dist/".

Note: the build script in this workspace copy prints only "build ok". Sizes below were measured separately with gzip -9.

## Measured bundle (gzip -9)

- app.js: 235,215 bytes raw, 62,558 bytes gzip.
- First load (index.html + styles.css + app.js): 63,585 bytes gzip. Budget: 300 KB.
  Not measured: transfer on a real slow 3G connection.

## Shipped-code checks (dist/app.js)

- Test-only strings (synthetic-seller-a, buyer-a, seller-a, driver-a, admin-a), vitest and test calls: 0 matches.
- Forbidden claims ("verified seller", "secured", "your money is held", "protected", "participating taxi", "youth-owned", "someone will contact you shortly"): 0 matches.
- Production project reference: 1 match, inside the guard that refuses it. Not shown on screen. Decision needed (same as increment 1).

## Claims check (new user-facing copy)

Checked by an automated test (src/strings/en.test.ts) against the forbidden list. Key claims:

- "Listings appear once sellers add stock." Describes the process, makes no promise.
- "Delivery and your total are worked out when you get your total." True: the server computes them.
- "Your total cannot be worked out yet, because sign-in codes cannot be sent yet." True while SIGN_IN_ENABLED is false.
- Route lines show the minimum and fee from delivery_routes, labelled as such.

## Not verified (must be stated before any claim of working)

1. Browser behaviour: no screenshot at 360 px, no Lighthouse, no Playwright run. This environment has no browser that I can drive.
2. Live reads: whether anonymous visitors can read products and delivery_routes depends on row-level security. Not checked against the live database from this build. If the read is denied, the catalog and routes panels show their load-error messages.
3. quote_order: it requires a signed-in buyer (auth.uid() not null). Anonymous visitors cannot call it, and sign-in is off. The quote path is wired and its response parser is tested, but it has never run against a real session.
4. The 360 px layout: styles reuse the increment-1 tokens. The new cards and buttons have not been viewed at 360 px.
5. Local database: no local Supabase stack was run here, so no integration test exists for this increment.

## What the buyer experiences today

A visitor can see listed produce (if RLS allows the read), add items to a basket, see the route minimums and fees, and see a clear message that the total needs sign-in. There is no total, and no order, until sign-in works.

## Known limitations

- Sign-in is the blocker for the total. It stays off until a provider is configured and tested.
- The route minimum is shown from the route table, but the server enforces it at quote time.
- Basket state is held in memory only. Nothing is stored on the device.

## Questions for the reviewer

1. Keep the production project reference inside the guard, or move it to build-time config? (Same question as increment 1.)
2. Is it acceptable to merge Increment 2 with the total disabled until sign-in exists, or should it wait?
3. Confirm the anonymous read policy on products and delivery_routes before merge (a read-only check on the live project).
