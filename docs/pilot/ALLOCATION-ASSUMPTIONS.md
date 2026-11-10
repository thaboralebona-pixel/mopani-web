# Allocation assumptions (Phase 4, P6)

**Status: for owner review. Nothing in this document is an approved commercial term. The working assumptions remain: seller 90% of product value, platform 10% of product value, driver and marshal share the delivery fee 2:1, subject to legal and commercial approval.**

## 1. Where each model appears

| #   | Model                                                                          | Location                                                                                                                                                                                                                                               | Type                                                                                                  | Active?                                                                                                                                                                         |
| --- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A   | **90 / 10 of product subtotal** (seller / platform)                            | `_apply_route_payout` (route orders): `v_platform = round(product_subtotal * 0.10, 2)`; `calculate_commission` route branch (`route_id IS NOT NULL`): platform fee 10%, seller earnings = subtotal minus platform fee                                  | Active code, route orders                                                                             | **Yes.** Route orders are created by `create_order_v2`, which is executable by signed-in users                                                                                  |
| B   | **80 / 10 / 5 / 5 of the total amount** (seller / platform / marshal / driver) | `calculate_commission` legacy branch (`route_id IS NULL`): platform 10%, marshal 5%, driver 5% of `total_amount`; seller earnings = total minus 20%                                                                                                    | Active code, non-route orders. **Trigger `commission_trigger` is attached to `orders` BEFORE INSERT** | Trigger is live. The path that creates non-route orders, `create_order` (legacy), is not executable by `anon` or `authenticated`. It is reachable only by service role or owner |
| C   | Driver and marshal share the delivery fee **1 : 1**                            | Legacy branch of `calculate_commission` (5% and 5%)                                                                                                                                                                                                    | Active code, legacy                                                                                   | Live only in the legacy branch                                                                                                                                                  |
| D   | Driver and marshal share the delivery fee **2 : 1**                            | Owner's working model. Route orders store `driver_delivery_share` and `marshal_delivery_share` on each order (`_apply_route_payout` pays them out). **The rule that sets the ratio is inside `create_order_v2` and was not read in full in this pass** | Working assumption; code path needs verification                                                      | Route orders                                                                                                                                                                    |
| E   | Association share taken out of the platform's 10%                              | `_apply_route_payout`: `association_earnings` = platform 10% × (taxi partner `revenue_share_pct` + non-member toll where driver's partner differs). Platform keeps the rest                                                                            | Active code. Values come from `taxi_partners`                                                         | Staging `taxi_partners` is **empty**, so the association share is zero on staging. Production not checked                                                                       |
| F   | 80 / 10 / 5 / 5 as a **legal scenario**                                        | Owner's note: "the latest report mentions an 80/10/5/5 split in the legal questions". The legal questions document is **not in this repository** and was not reviewed                                                                                  | Legal scenario                                                                                        | Not a code rule by itself                                                                                                                                                       |
| G   | 80 / 10 / 5 / 5 in pilot documents                                             | `PILOT-LAUNCH-CHECKLIST.md` (counsel question), `ROUTE-PRICING-VERIFICATION.md` (noted as a proposal). These documents refer to it; they do not set it                                                                                                 | Documentation only, marked as not agreed                                                              | No                                                                                                                                                                              |

Searched: repository (all files, excluding dependencies) and both databases' function definitions (`0.8`, `0.9`, `0.1`, `0.05`, `0.5`, `0.3`, `0.2` literals). Matches are the functions listed above and `refund_order`, `quote_order` (fee and minimum logic, not allocation).

## 2. Classification

- **Active code assumption (conflict):** Model B is live in the database for non-route orders. Model A is live for route orders. The two models give different results for the same R100 of product value. A non-route order of R100 on a 0 delivery fee gives the seller R80 (model B) while a route order gives R90 (model A).
- **Historical proposal:** not determinable from the repository. The legacy branch looks like the first model, retained when routes were introduced.
- **Legal scenario:** model F, as described by the owner.
- **Unapproved commercial proposal:** model B as a commercial split is not approved. Model A is the working assumption, also not yet approved.

## 3. Consistency problems

1. **Two live payout models.** The legacy branch and the route branch both exist and both pay out. Which one runs depends on whether `route_id` is set. A non-route order can still be created through service-role code.
2. **Different bases.** Model B takes 10% of the total, including the delivery fee and the card fee. Model A takes 10% of product subtotal only. The platform's share of delivery is different under each.
3. **Driver and marshal ratio.** Model B gives 1 : 1. Working model gives 2 : 1.
4. **Card processing fee.** `_apply_route_payout` adds the card processing fee to `platform_wallet.processing_reserve`. Not part of either split above; not described in the working model.
5. **Association share.** Comes out of the platform's 10%. The owner has said 30% of the platform's 10% is the taxi association's share. Not agreed. Database value is not set on staging.

## 4. Recommended decisions for the owner

1. Confirm model A (90/10 on product subtotal) as the working assumption for the pilot, subject to counsel.
2. Confirm the delivery split (2:1) and where it is set in `create_order_v2`.
3. Decide whether the legacy branch (model B) is disabled. Recommended: no direct execution path is needed by app roles; confirm no service-role process creates non-route orders. If none exists, remove the commission trigger's legacy branch in a later reviewed change. **Not changed in this pass.**
4. Confirm the association percentage is not entered in `taxi_partners` until the association agreement is signed.
5. Give counsel the working model (model A and D) and ask them to confirm, rather than the 80/10/5/5 scenario alone.

## 5. What was not changed

No allocation function, trigger, value or document was changed. Model B remains in the database.
