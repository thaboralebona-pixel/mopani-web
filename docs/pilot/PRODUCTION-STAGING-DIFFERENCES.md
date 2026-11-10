# Production versus staging differences (Phase 4, P3, SEC-06)

Production: project `ProjectX` (`jpjjdzlhthvookllydai`). Staging: `mopani-staging` (`exohydsjywelbhhswswh`). Read-only inspection on 10 Nov 2026. Production is **not** changed. No production migration has been executed.

## 1. Identical (verified by definition hash or grant query)

- `quote_order`: identical (md5 `c25bb2d7…`).
- `request_withdrawal_v2`, `approve_withdrawal`, `mark_payout_settled`, `request_subscription`, `sa_id_is_youth`, `admin_force_cancel`, `is_admin`, `enforce_kyc_on_withdrawal`, `guard_seller_privileged_fields`: identical definitions.
- Grants on those functions: identical.
- `seller_kyc`, `seller_wallets`, `seller_withdrawals` policies and grants: identical.
- `public_driver_profiles` and `public_marshal_profiles`: identical (owner rights, authenticated SELECT).

## 2. Differences

| Object                                         | Production                                                                                                                                | Staging                                                                                                           | Effect on production                                                                                                                                                                                                                   |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `products` SELECT                              | `public can read` = true for everyone                                                                                                     | `public can read listed products` (`is_available = true`, anon and authenticated) and `sellers read own products` | Anonymous visitors see unlisted and draft products                                                                                                                                                                                     |
| `orders` SELECT                                | `Seller can view their product orders` (any order containing the seller's product) and `seller view own sales` (`seller_id = auth.uid()`) | Neither exists. Replaced by `seller_sales()`                                                                      | **Sellers read full order rows, including `buyer_id`, `delivery_address` (jsonb), `stripe_session_id`, `stripe_payment_intent`, `tracking_number`, `delivery_fee`, `driver_delivery_share`, `marshal_delivery_share`, `destination`.** |
| `deliveries` SELECT                            | `deliveries_participant_read`: buyer or seller of the order reads the full delivery row                                                   | Dropped. Replaced by `buyer_delivery()` (status and times and proof URL, no driver or marshal id)                 | **Buyers and sellers read `driver_id`, `marshal_id`, `pickup_address`, `collection_photo_url`, `proof_of_delivery_url`, `load_size`, `distance_km`**                                                                                   |
| `marshal_wallet` SELECT                        | no policy                                                                                                                                 | `marshal_wallet_own_read` (authenticated, own)                                                                    | Production: marshals cannot read their own balance (functional gap)                                                                                                                                                                    |
| `wallet_transactions` SELECT                   | seller only                                                                                                                               | seller, plus `driver reads own transactions` and `marshal reads own transactions`                                 | Production: drivers and marshals cannot see their own transactions (functional gap)                                                                                                                                                    |
| `driver_marshal_transactions`                  | `driver_marshal_own_read` (same on both)                                                                                                  | same                                                                                                              | none                                                                                                                                                                                                                                   |
| Functions `seller_sales()`, `buyer_delivery()` | absent                                                                                                                                    | present (authenticated only)                                                                                      | Replacement paths do not exist on production yet                                                                                                                                                                                       |
| Storage `delivery-proof` (private)             | `delivery_proof_participant_read`: admin, order buyer or seller, or assigned driver can read photos for that order                        | **No policy on staging** (bucket present, no read policy)                                                         | Staging proof photos are unreadable by everyone except via service role. Staging test gap                                                                                                                                              |
| Storage `product-photos` (public)              | bucket and 2 policies (public read, seller delete own folder)                                                                             | **bucket absent**                                                                                                 | Staging has no product photo storage. Staging test gap                                                                                                                                                                                 |

## 3. Which differences expose buyer addresses to sellers

- **Confirmed:** production policy `Seller can view their product orders` returns the full `orders` row for any order containing the seller's product. `orders.delivery_address` (jsonb) is in that row. Any seller of any item in a multi-seller order can read the buyer's delivery address.
- **Confirmed:** the same policy and `seller view own sales` return `buyer_id` for those orders.
- Not exposed on staging: staging has neither policy on `orders`. Sellers get only the summary columns from `seller_sales()`, which excludes `delivery_address` and `buyer_id`.

## 4. Impact on each role (for owner review)

| Role              | Production today                                                                           | After SEC-06 migration                                                                                          | Functional consequence                                                                                                                                                                       |
| ----------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Buyer             | Reads own orders. Reads delivery row including driver and marshal ids and collection photo | Reads own orders. Reads only status, times and proof URL via `buyer_delivery()`                                 | Buyer no longer sees driver/marshal ids (owner decision already: no). Buyer loses direct delivery row (not used by the app)                                                                  |
| Seller            | Reads any order containing their product, including buyer address and buyer id             | Reads only order summary via `seller_sales()` (no address, no buyer id). Reads own products, including unlisted | **Seller can no longer see buyer delivery address.** Sellers will need an address-free view to pack and label. Seller packing workflow must be designed. This is the intended privacy change |
| Driver            | Reads deliveries assigned to them (policy `deliveries_driver_read`, unchanged)             | Unchanged. Wallet read added only if the wallet policies are also migrated (optional step 5)                    | none for deliveries                                                                                                                                                                          |
| Marshal           | Reads deliveries assigned to them (unchanged). No own-wallet read                          | Unchanged. Own-wallet read added only if optional step 5 is applied                                             | Marshal balance display only                                                                                                                                                                 |
| Anonymous visitor | Sees all products including unlisted and draft                                             | Sees only listed products                                                                                       | Unlisted products disappear from the public catalogue. Intended                                                                                                                              |
| Admin             | Full read (`is_admin()` policies unchanged)                                                | Unchanged                                                                                                       | none                                                                                                                                                                                         |

Seller packing: the seller needs to know what to pack and which marshal collects. Neither needs the buyer's address. Recommendation: a `seller_pickup(order_id)` function returning items, quantities and collection time only. Not built; contract to be agreed.

## 5. Production migration

File: `docs/pilot/remediation/PHASE4-PRODUCTION-SEC-06-migration.sql` (draft, **not executed, not approved**).

Contents: drop 3 production policies, add 2 product policies, add 2 functions with the exact staging definitions and grants, verify, commit. Rollback block recreates the captured production policies with their exact expressions.

Optional step 5 (wallet read policies for marshal and driver transactions): **not included** in the SEC-06 draft. It is a functional addition and needs its own approval.

## 6. Preconditions before production approval

1. Staging test of the same migration passes (`docs/pilot/remediation/PHASE4-01-tests.sql` covers SEC-01 to SEC-04 only; a SEC-06 staging test is still to be written and run on staging).
2. Owner accepts the seller packing gap (section 4).
3. Production policy list and grants captured immediately before running (rollback baseline).
4. Production storage policies checked (not done in this pass beyond `delivery-proof` and `product-photos`).
5. Written owner approval for this exact file.

## 7. Staging gaps found while comparing

- Staging has no storage read policy on `delivery-proof`: the buyer's proof-photo link from `buyer_delivery()` cannot be opened by the buyer on staging. Fix before the staging order journey test.
- Staging has no `product-photos` bucket.
- Staging has no seller read of `orders`, so no staging test can yet confirm the seller's order list path (`seller_sales()` is the only route).
