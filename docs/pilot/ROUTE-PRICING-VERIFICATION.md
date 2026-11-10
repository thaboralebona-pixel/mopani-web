# Route and pricing verification

Purpose: confirm that the prices the app shows match the approved database configuration, and that the owner has confirmed each number. The app must not hold a separate price list.

## Source of truth

- Route minimums and delivery fees: `delivery_routes` table, read by the app.
- Totals: `quote_order` server function. The browser displays and does not calculate totals.

## Check procedure

1. Read `delivery_routes` on staging and production (read-only). Record origin, destination, minimum basket, delivery fee.
2. Compare each value with the owner's confirmed figure. Record the owner's confirmation and date.
3. Compare each product's unit price and weight with the owner's confirmed list.
4. Run a test quote for a 1 kg, 5 kg and 6 kg basket and check the billable block count (1, 1, 2).
5. Run a test quote for a basket below the minimum and confirm the error message.

## Known figures (to verify, not yet confirmed as final)

- Origins: Elim and Tshakhuma (owner-named). Destination: Johannesburg.
- Owner-reported product prices (per unit as stated in the owner's notes): atchar, mashonzha, peanuts, madzhulu / magege. Mashonzha prices were given in conflicting forms ("1 kg is 55" and "R75 for mashonzha 1 kg; 5 kg at R80", then "55 new price"). **Owner must confirm the single correct figure for each product and size before any listing.**
- Revenue split 80/10/5/5 is a proposal. The taxi association share (30% of the platform's 10%) is not agreed.

## Status

- Route data: read from the database; owner confirmation pending.
- Product prices: conflicting notes; owner confirmation pending.
- Quote tests: to be run on staging with a signed-in test buyer (blocked until sign-in works).

## Legal review required

Any statement of the revenue split, any description of escrow, and any fee presented to sellers or buyers. (LEGAL)
