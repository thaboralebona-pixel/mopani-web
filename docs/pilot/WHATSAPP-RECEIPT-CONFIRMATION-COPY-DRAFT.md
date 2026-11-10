# WhatsApp receipt confirmation: copy draft and phone-identity design

Date: 2026-11-10. **Draft for review. Nothing has been deployed.** Decision 42: wording change approved in principle; production deployment **not authorised**.

---

## 1. Source and version evidence

The repository contains no Edge Function source. The deployed source was recovered through an authorised read-only route: the Supabase management tooling's "get Edge Function" call, which returns the files of the deployed version. No deployment or change was made.

| Function            | Deployed version | Last updated (UTC) | Bundle SHA-256 (as reported by Supabase)                           | Read       |
| ------------------- | ---------------- | ------------------ | ------------------------------------------------------------------ | ---------- |
| `whatsapp-webhook`  | 8                | 2026-10-12 11:17   | `b0f003d57e478a472e620ab2893832aa81b96663861c8e95705553958aedb231` | 2026-11-10 |
| `dispatch-whatsapp` | 7                | 2026-07-26 18:17   | `c5737bc84e376f58411358aca6c8be8bf144776036b034a16c4463e54c9dd01e` | 2026-11-10 |

Everything quoted in section 2 is copied from `whatsapp-webhook` version 8, file `index.ts`, as returned on 2026-11-10. If the function is redeployed, this section must be re-verified against the new version before any change.

**Not recoverable from here:** the text of the Meta-approved message templates (`delivery_confirmation_buyer`, `order_paid_vendor`, `driver_cargo_alert`). `dispatch-whatsapp` sends only the template name, the order number and button payloads. The template body lives in WhatsApp Manager under the business account. Its wording is **unverified**. The owner (or whoever holds the Meta business account) must export it.

Recommendation: copy both function sources into the repository under version control (decision 29, still open), so wording can be reviewed in a pull request.

---

## 2. Exact current wording (verified, `whatsapp-webhook` v8)

Replies to a tap on **Confirm Receipt** (`confirm_receipt`):

| #   | Condition               | Current reply                                                                          |
| --- | ----------------------- | -------------------------------------------------------------------------------------- |
| C1  | RPC returned an error   | `Something went wrong. We are looking into it.`                                        |
| C2  | Already confirmed       | `Order #${orderId} was already confirmed. Nothing more to do.`                         |
| C3  | **Confirmed**           | `Thank you! Order #${orderId} is confirmed. The seller and driver have been credited.` |
| C4  | Sender is not the buyer | `This number is not the buyer on that order, so we cannot confirm it here.`            |
| C5  | Any other failure       | `We could not confirm that order. Please check the app.`                               |

Replies to **Report a problem** (`report_problem`):

| #   | Condition             | Current reply                                                                                                                          |
| --- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | `payments_live` true  | `Thank you for telling us. Someone will contact you shortly. Your payment stays held while we look into it.`                           |
| P2  | `payments_live` false | `Thank you for telling us. Someone will contact you shortly. Please also tell us in the Mopani app so the order is marked for review.` |

Observations (**Confirmed** from the source):

- C3 states that the seller and driver "have been credited". It is sent whenever the database function reports success. It does not depend on `payments_live`, although the function reads that switch for P1 and P2.
- C4 tells an unknown sender that an order exists and that their number is not its buyer.
- P1 says "Your payment stays held". No payment evidence exists in the system.
- The header comment says "This endpoint can release escrow. A tap on [Confirm Receipt] credits a seller and a driver."
- Personal data in logs: on a status-lookup failure the function logs the sender's phone number to the function log (`console.error(..., { from, ... })`); `report_problem` writes the sender's number into `admin_audit_log.after_data`; a failed delivery writes the recipient's number there too.

If containment is applied (draft, not approved), the RPC is refused and the buyer receives **C1**. C3 can no longer be reached.

---

## 3. Proposed replacement wording

Principles: no claim that anyone has been credited or paid; no claim that money was received or is held; delivery confirmation is not settlement; no settlement date; no internal security detail; plain English a buyer on a low-end phone can read in one screen.

### 3.1 While receipt confirmation is unavailable (containment period)

| #          | Condition               | Proposed reply                                                                                                                                                                                                                         |
| ---------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C1, C3, C5 | Any Confirm Receipt tap | `Thank you. We have your message about order #{order}. Confirming receipt by WhatsApp is not available right now. You do not need to do anything else. If something is wrong with your order, tap Report a problem or contact Mopani.` |
| C2         | Already recorded        | `Order #{order} is already recorded as received. Nothing more to do.`                                                                                                                                                                  |
| C4         | Sender not recognised   | `We could not match this number to that order. Please contact Mopani if you need help.`                                                                                                                                                |

### 3.2 When receipt confirmation is available again (after the payment guard is live)

| #      | Condition        | Proposed reply                                                                  |
| ------ | ---------------- | ------------------------------------------------------------------------------- |
| C3     | Receipt recorded | `Thank you. Order #{order} is recorded as received.`                            |
| C1, C5 | Could not record | `We could not record that right now. Please try again later or contact Mopani.` |

No sentence about sellers, drivers, credit or payment appears in any confirmation reply. Settlement is communicated separately, only from a verified settlement record (see `PHASE5B5-GUARD-ARCHITECTURE.md`, section 9).

### 3.3 Report a problem

| #      | Condition | Proposed reply                                                                                                                               |
| ------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| P1, P2 | Always    | `Thank you for telling us. Someone from Mopani will contact you. Please also report it in the Mopani app so the order is marked for review.` |

"Your payment stays held" is removed in both branches.

### 3.4 The outbound template

While confirmation is unavailable, the `delivery_confirmation_buyer` template still shows a **Confirm Receipt** button. Recommendation (decision 48, not approved): stop queueing `order_delivered` WhatsApp notifications during containment, or replace the template with one that has no confirm button. Changing a Meta template needs Meta's approval and is the account holder's action.

### 3.5 Internal comment

Replace the header comment so it does not describe the endpoint as crediting anyone. Suggested: "This endpoint records a buyer's statement that goods were received. It does not move money."

---

## 4. Phone identity and WhatsApp security design (Workstream F)

No production or staging phone record was read in detail or changed. Production holds 3 profiles and none has a phone number.

### 4.1 Findings (confirmed in Phase 5B-4)

Users choose their own number; ownership is never verified; uniqueness is on raw text while matching uses the normalised number; lookups take the first matching profile; a mistyped or unowned number gives a stranger the Confirm Receipt button; phone numbers are stored in plain text in audit rows and function logs.

### 4.2 Required design

| #   | Requirement                | Design                                                                                                                                                                                                             |
| --- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Verified ownership         | A number is usable for any action only after a one-time code sent to it is entered in the signed-in app. Store `phone_verified_at`. Changing the number clears verification                                        |
| 2   | Canonical form             | Store E.164 (`+27821234567`) in a separate column `phone_e164`, written only by the verification function. Users cannot write it directly                                                                          |
| 3   | Uniqueness                 | Unique index on `phone_e164`. One verified number, one profile                                                                                                                                                     |
| 4   | Fail closed on collision   | Lookups by number must return exactly one verified profile. Zero or more than one: refuse and log. Remove `LIMIT 1`                                                                                                |
| 5   | Order and buyer binding    | A confirmation is accepted only if the token (below) belongs to that order and that buyer. The sender's number is a second check, not the identity                                                                 |
| 6   | Single-use, expiring token | The button payload carries a random token (at least 128 bits), not the bare order id. The database stores only its hash, with order id, buyer id, expiry (for example 72 hours) and `used_at`                      |
| 7   | Replay protection          | Token marked used in the same transaction as the receipt record. Message id stored and unique. A second tap is a no-op with the "already recorded" reply                                                           |
| 8   | Minimal phone exposure     | Audit rows and logs carry the profile id and the last 2 digits only, or a keyed hash. Never the full number or message body                                                                                        |
| 9   | Retention and access       | WhatsApp audit rows: readable by active admins only, through a logged function; retained 12 months (owner to confirm with counsel under POPIA), then deleted or anonymised. Function logs: no phone numbers at all |

A receipt confirmation is a **statement by the buyer**. It never authorises a wallet credit. Release depends on the payment guard.

### 4.3 Not to be done now

No phone column, index, token table or verification function is created in this phase. No existing phone value is changed.

---

## 5. What needs approval before any of this ships

| Item                                          | Needed                                                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Deploy changed `whatsapp-webhook`             | Separate written approval; source in the repository first; staging rehearsal with a staging WhatsApp number |
| Stop or change the `order_delivered` template | Owner decision 48; Meta account holder action                                                               |
| Export current template texts                 | Account holder                                                                                              |
| Phone verification build                      | Owner decision 45 (open)                                                                                    |
