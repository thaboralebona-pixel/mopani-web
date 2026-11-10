# KYC and personal information review (Phase 4, P5)

Evidence: staging and production column lists and policies (read-only, 10 Nov 2026). Frontend: `src/` contains no reference to `seller_kyc`, `kyc` or `id_number`.

## 1. Columns in `seller_kyc`

| Column                        | Type        | Personal or financial                    | Seller needs it            | Admin needs it      | Frontend uses it | Notes                                                                          |
| ----------------------------- | ----------- | ---------------------------------------- | -------------------------- | ------------------- | ---------------- | ------------------------------------------------------------------------------ |
| `seller_id`                   | uuid        | identifier                               | yes (own row)              | yes                 | no               | key                                                                            |
| `kyc_status`                  | text        | verification state                       | **yes** (own status)       | yes                 | no               | protected by `guard_seller_privileged_fields`                                  |
| `rejection_note`              | text        | admin notes, may contain personal detail | yes (reason for rejection) | yes                 | no               | protected by trigger for non-admin writes; **readable by owner**               |
| `submitted_at`, `verified_at` | timestamptz | status dates                             | yes                        | yes                 | no               | low                                                                            |
| `verified_by`                 | uuid        | admin identifier                         | no                         | yes                 | no               | reveals which admin verified; should not be seller-visible                     |
| `verified_youth`              | boolean     | derived age-band flag                    | no                         | limited             | no               | derived by `compute_verified_youth()`. **Youth-owned claims are not approved** |
| `id_number`                   | text        | **South African ID number (personal)**   | no (own, once entered)     | yes (verification)  | no               | **Stored as plain text (column type text, no encryption evidence)**            |
| `bank_account`                | text        | **bank account number (financial)**      | no (not needed in pilot)   | yes (payout, later) | no               | **Stored as plain text**                                                       |
| `bank_name`, `bank_branch`    | text        | financial                                | no                         | yes                 | no               | low on their own                                                               |
| `id_doc_url`                  | text        | link to ID document                      | no (after upload)          | yes                 | no               | location of document unknown (see section 4)                                   |
| `proof_of_addr`               | text        | link to address proof                    | no (after upload)          | yes                 | no               | location unknown                                                               |

## 2. Exposure through the API (confirmed)

- Policy `kyc_own_read`: `seller_id = auth.uid()`, **no column restriction**. Any signed-in seller reads every column of their own row, including `id_number`, `bank_account`, `id_doc_url`, `proof_of_addr`, `verified_by`, `rejection_note`, `verified_youth`.
- The table grants `authenticated` SELECT and DELETE. There is no DELETE policy, so deletes are refused today. The DELETE grant is excess.
- Writes: `kyc_own_insert` and `kyc_own_update` let the seller write their own row. `kyc_own_update` is limited to rows not yet `verified`. The guard trigger prevents setting `kyc_status`, `verified_*`, `rejection_note` or `verified_youth` from a non-admin role (verified by trigger body).
- Functions: `enforce_kyc_on_withdrawal` reads `kyc_status` only. `compute_verified_youth`, `emit_trust_on_kyc`, `audit_kyc_change` are not executable by app roles. `audit_kyc_change` writes to the audit log; its content was not read in this pass (open item).

## 3. Least-privilege design (recommendation; not applied)

The seller's own row remains, but the sensitive columns are removed from the seller's column grant:

- Revoke SELECT on `seller_kyc` from authenticated.
- Grant SELECT on `seller_kyc (seller_id, kyc_status, rejection_note, submitted_at, verified_at)` to authenticated. Keeps the seller's status and the reason for rejection.
- Keep admin reads through `is_admin()`: an admin-only function returning the sensitive fields with an audit entry, or a column grant to a dedicated admin role.
- Revoke DELETE from authenticated (no code path).
- Store `id_number` and `bank_account` encrypted or tokenised (design needed; **a schema change, requires separate approval**). For the pilot, the minimum is to **not collect bank account numbers** until payments are enabled.
- Do not let the seller read `verified_by` or `verified_youth`.

Impact on the seller: the seller can see their status and any rejection reason but cannot read back the ID number or bank account they entered. The app does not currently display either, so this does not break a current screen. Impact is confined to any future seller screen that shows KYC data, which must not be built without this design.

Impact on the admin: admins need the full row for verification. Route through an admin function with audit, not a broad grant.

## 4. Storage of supporting documents

- Production storage buckets: `delivery-proof` (private, policies for order participants and admins) and `product-photos` (public). **No KYC bucket exists on production.**
- Staging storage buckets: `delivery-proof` (private, **no policy**) and no `product-photos`. No KYC bucket.
- `id_doc_url` and `proof_of_addr` are text fields. Their storage location is therefore either an external URL, a path in an undocumented bucket, or unused. **Owner to confirm where uploaded KYC documents are actually held.** If they are held in a public bucket, that is a critical finding. Not established in this pass.

## 5. Plaintext storage and logging

- `id_number` and `bank_account` are `text` columns with no encryption evidence in the schema.
- Logging: `audit_kyc_change` writes to `admin_audit_log`. Its body was not read in this pass. Whether it logs before and after values (which would copy the ID number into the log) is **unverified**.
- Supabase database logs and API gateway logs may retain request bodies if enabled. Owner to check log retention (not checked).

## 6. Legal and POPIA questions for counsel

1. Is an SA ID number "personal information" requiring special handling under POPIA for this purpose, and what lawful basis applies?
2. Is storing a full bank account number before payments are enabled necessary? Counsel to advise on minimisation.
3. Retention periods for KYC data, and deletion on request.
4. Whether the youth-verification flag (`verified_youth`) is itself a regulated classification and whether it can be stored at all.
5. Whether seller-visible rejection notes can contain personal information about third parties.
6. Cross-border transfer if the database or any processor is outside South Africa (region shows eu-central-1 for both projects; counsel to confirm the processing arrangement).
7. Whether the platform is the responsible party or an operator for seller KYC data.

## 7. Recommended order

1. Owner confirms where KYC documents are held (section 4). This is the highest-risk unknown.
2. Staging: apply column-level revoke on `seller_kyc` (design above) after writing a test. **Requires separate approval.**
3. Decide whether bank account collection is deferred until payments are enabled.
4. Plan encryption of `id_number` and `bank_account` before any real seller is onboarded with KYC data.
