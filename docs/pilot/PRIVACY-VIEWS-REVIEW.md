# Driver and marshal public views: privacy review (SEC-02)

Scope: staging definitions read 10 Nov 2026. Nothing applied. Production not checked for these views beyond the grant result in the register.

## What the views are

Both views are owned by `postgres` and run with owner rights (`security_invoker=false`). That means they read the base table without applying the base table's row-level security. Any signed-in user can read them.

| Object                    | Base table         | Filter            | Grants                             |
| ------------------------- | ------------------ | ----------------- | ---------------------------------- |
| `public_driver_profiles`  | `driver_profiles`  | `verified = true` | authenticated: SELECT. anon: none. |
| `public_marshal_profiles` | `marshal_profiles` | `verified = true` | authenticated: SELECT. anon: none. |

Base-table RLS (for comparison): `driver_profiles` and `marshal_profiles` allow SELECT only where `profile_id = auth.uid()`. So a driver sees their own row, and no one else's row, when querying the table directly. The view bypasses that.

## Column-by-column exposure

| Column             | driver view       | marshal view      | Who needs it                                       | Sensitivity                                                      | Needed by the pilot app?                                             |
| ------------------ | ----------------- | ----------------- | -------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------- |
| `id`               | yes               | yes               | internal key                                       | low (joins to deliveries)                                        | Only for admin screens                                               |
| `profile_id`       | yes               | yes               | **links the view to the person's sign-in account** | **high**: a user ID that can be used to match identities         | No                                                                   |
| `taxi_partner_id`  | yes               | yes               | which taxi association the person belongs to       | **high**: association membership, affects operator relationships | No                                                                   |
| `verified`         | yes (always true) | yes (always true) | tells a visitor the person is verified             | medium: a verification claim                                     | No                                                                   |
| `verified_at`      | yes               | yes               | date of verification                               | low-medium                                                       | No                                                                   |
| `rating`           | yes               | yes               | performance score                                  | medium: a reputation record about a person                       | No, not for the pilot                                                |
| `total_deliveries` | yes               | yes               | performance count                                  | low-medium                                                       | No                                                                   |
| `active`           | yes               | yes               | whether the person is working                      | medium: availability                                             | No                                                                   |
| `vehicle_type`     | yes               | no                | vehicle class (driver only)                        | medium: links a person to a vehicle                              | Buyer may need it for "your driver: minibus taxi". Not required now. |
| `max_load_kg`      | yes               | no                | vehicle capacity                                   | low                                                              | No                                                                   |

No name, phone, email or ID number is in either view. But `profile_id` lets any signed-in user join the view to `profiles` through a separate query, if `profiles` exposes names to them. `profiles` RLS allows only the owner to read their own row, so the join is blocked there. The `profile_id` still tells a user which auth account the driver is, and that is the link we don't want to expose.

## Does the frontend need these views?

No. The only `.from()` and `.rpc()` calls in `src/` are `products`, `delivery_routes` and `quote_order`. Neither view is referenced. The grep was repeated on this branch on 10 Nov.

## Does the database depend on them?

No. A catalogue search found no function and no view that references either view (SEC-02 dry-run check).

## Is revoking enough?

For the pilot, yes, because nothing depends on the views. For the long term, no: a buyer may later need "your driver's first name and vehicle", and a seller may need "your marshal's name". Those needs should be met by narrow functions that return only the required columns for a specific order, not by a broad view.

## Recommended minimum by role

| Role                         | Needs                                                  | Should not see                                           |
| ---------------------------- | ------------------------------------------------------ | -------------------------------------------------------- |
| Buyer (for their own order)  | driver first name, vehicle type, status                | driver ID, profile ID, partner, rating, other deliveries |
| Seller (for their own order) | marshal first name at the origin rank, collection time | buyer address, driver ID, profile ID, partner            |
| Driver                       | own profile, own deliveries, own transactions          | other drivers' rows, marshal balances                    |
| Marshal                      | own profile, own balance, own deliveries               | other marshals' balances, driver ratings                 |
| Admin                        | everything, through admin-only functions with audit    | (no restriction beyond the audit trail)                  |

## Secure replacement design (for owner approval)

1. **Pilot (now):** revoke SELECT on both views from `authenticated` and `anon`. Keep the views so nothing breaks structurally. Draft in `docs/pilot/remediation/SEC-02-privacy-views.sql`.
2. **Before any buyer or seller sees a driver or marshal name:** create two SECURITY DEFINER functions, for example `order_driver_summary(order_id)` and `order_marshal_summary(order_id)`. Each checks `auth.uid()` is the buyer or seller of that order, and returns only the agreed columns. Neither returns `profile_id`, `taxi_partner_id` or `rating`.
3. **Retire the views** once the functions are in use, after a dependency check.
4. If the views are kept for admin use, set `security_invoker = true` so base-table RLS applies, and grant only to `authenticated` users who are active admins.

## Verification

- After revoke: `has_table_privilege('authenticated','public.public_driver_profiles','SELECT')` returns false, and the same for the marshal view and for `anon`.
- Dry-run inside a transaction on staging and rolled back: both returned false inside the transaction, and both returned true again after the rollback.
- Frontend smoke test: the catalogue, routes and quote still load (no call to these views).

## Rollback

`grant select on public.public_driver_profiles, public.public_marshal_profiles to authenticated;`
