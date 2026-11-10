# Phase 5B-5: staging preparation plan

Date: 2026-11-10. **Plan only.** Decisions 43 and 44: staging preparation and guard SQL authoring are approved; **staging changes and test execution are not authorised**. No staging change was made. Staging was read with `SELECT` queries and the read-only Edge Function listing.

Staging project: `exohydsjywelbhhswswh` ("mopani-staging", created 2026-11-03). Production: `jpjjdzlhthvookllydai` ("ProjectX").

---

## 1. Current staging state (**confirmed** 2026-11-10)

| Item                                                                | Staging                                                                                         | Note                                              |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| Payout, confirmation, dispute, refund and withdrawal functions      | Same source hashes and grants as production (functions compared in Phase 5B-4)                  | Function logic can be rehearsed                   |
| `pg_cron`, `pg_net`, `pgtap`, `http`                                | **Not installed** (all four are available to install)                                           | No schedules, no outbound HTTP, no test framework |
| `cron`, `net`, `supabase_migrations` schemas                        | Absent                                                                                          | No migration history table on staging             |
| Vault                                                               | **No secrets stored**                                                                           | Notification functions would find no secret       |
| Functions containing the production project reference               | `private.post_notification`, `private.invoke_whatsapp_dispatcher`, `public.guard_product_image` | Three, not two. The third was found in this pass  |
| Notification trigger `trg_dispatch_notification` on `notifications` | **Enabled**                                                                                     | Fires on insert                                   |
| Pending notifications                                               | **14**                                                                                          | Would be picked up if dispatch were enabled       |
| Edge Functions                                                      | `dispatch-notification` v7 only                                                                 | No WhatsApp functions on staging                  |
| `app_config.payments_live`                                          | Row absent                                                                                      | Code treats absent as false                       |
| Active admins                                                       | 0                                                                                               | Admin-gated functions cannot be exercised         |
| Auth users / profiles / orders                                      | 4 / 4 / 7 (none flagged as test orders)                                                         | Existing data, origin not reviewed                |
| `orders.escrow_status` default                                      | `holding`                                                                                       | Same defect as production                         |

**Hazard to note before anything is enabled:** if `pg_net` were installed today, the enabled trigger and the 14 pending rows would attempt HTTP calls to the **production** function URL. The calls would probably fail for lack of a secret, but that must not be left to chance.

---

## 2. Separation plan

Each step lists what it achieves and how it is verified. Order matters: steps 1 to 4 come before any extension is enabled.

### 2.1 Independent staging notification endpoint

- Replace the hardcoded production URLs in `private.post_notification` and `private.invoke_whatsapp_dispatcher` with a value read from a staging configuration row (for example `app_config.functions_base_url`), so no project reference is compiled into a function body. Apply the same pattern to production later, under its own approval.
- Review `public.guard_product_image`: it contains the production reference, most likely a storage URL check. Staging needs its own project reference there, or uploads will be judged against the wrong project.
- Verify: `select proname from pg_proc where prosrc like '%jpjjdzlhthvookllydai%'` on staging returns zero rows.

### 2.2 Independent staging secrets and credentials

- Staging gets its **own** values for every secret: webhook secret, WhatsApp test credentials, email provider key, payment-provider test key. Created fresh by the owner in the staging project. Never copied from production.
- Secrets are entered by the owner in the Supabase dashboard. They are not pasted into chat, issues, commits or documents.
- Staging vault receives a staging-only `mopani_webhook_secret` (name may match; value must differ).
- Verify by name only: list secret names on both projects; confirm with the owner that values were generated separately. Values are never read or compared by Claude.

### 2.3 Staging cannot call production notification services

- After 2.1, the staging database holds no production URL.
- Production's `dispatch-notification` and `dispatch-whatsapp` authenticate callers with a shared secret. Because staging's secret differs (2.2), a staging call would be rejected even if a URL were wrong.
- Email: staging uses a provider sandbox or a staging-only sending domain, with an allow-list of recipient addresses controlled by the owner.
- WhatsApp: staging uses a Meta **test** number and test recipients. No WhatsApp function is deployed to staging until that exists.
- Before `pg_net` is enabled: disable `trg_dispatch_notification` and mark the 14 pending notifications as cancelled (a staging data change, needs approval), then re-enable deliberately.
- Verify: with dispatch enabled, insert one staging notification and confirm from staging function logs that only the staging endpoint was called, and from production logs that nothing arrived.

### 2.4 Project and environment separation

- Two Supabase projects, already separate. Keep it that way: no shared database, no shared keys, no cross-project function calls.
- Frontend: staging build reads staging URL and publishable key from its own untracked `config.js`. The repository carries only `config.example.js` with placeholders.
- Access: list who can open each project in the Supabase organisation; production access limited to the owner (owner action).
- Staging gets a migration history table so that changes are recorded from now on. Today staging has none, so its schema cannot be traced to a migration list.
- Never run a script against a project chosen by default. Every script names its target project and checks it (`select current_database()`, plus a project marker row) before doing anything.

### 2.5 Extensions and their purpose

| Extension | Purpose on staging                                                                               | Risk                                                                                                                                                                              | Enable when                             |
| --------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `pgtap`   | Run the regression suite and the new guard tests                                                 | Installs many helper functions; install into a dedicated `tap` schema, not `public` (production has it in `public`, where 22 dynamic-SQL helpers are callable by signed-in users) | After 2.1 to 2.4                        |
| `pg_cron` | Rehearse scheduled release, sweeps, auto-cancel                                                  | Jobs act on their own; create them disabled, enable one at a time                                                                                                                 | After guard SQL is applied on staging   |
| `pg_net`  | Outbound calls for notifications and dispatcher                                                  | Cross-environment calls if URLs are wrong                                                                                                                                         | **Last**, after 2.1 to 2.3 are verified |
| `http`    | Only if the guard design uses database-side provider verification (option A in the architecture) | Synchronous outbound calls from the database                                                                                                                                      | Only if that option is chosen           |

### 2.6 Test identities and roles

| Identity               | Role                                         | Notes                                                        |
| ---------------------- | -------------------------------------------- | ------------------------------------------------------------ |
| `buyer_a`, `buyer_b`   | authenticated buyers                         | Two, to test cross-buyer access                              |
| `seller_a`, `seller_b` | sellers                                      | Two, to test seller isolation                                |
| `driver_a`             | verified driver                              | Plus `driver_unverified`                                     |
| `marshal_a`            | verified marshal                             |                                                              |
| `admin_a`, `admin_b`   | active admins                                | Two, because approval of an admin requires a different admin |
| `outsider`             | signed-in user with no relation to the order | For dispute and access tests                                 |
| service role           | staging service key                          | Used only by the test harness                                |
| `payment_writer`       | staging-only writer role                     | From the guard design                                        |

All are staging-only accounts with obviously fake details (for example names beginning `TEST`, phone numbers from a reserved test range agreed with the owner, no real ID or bank data). No production user is copied.

### 2.7 Fixtures and cleanup

- Fixtures are created by one script, tagged with a run id, and flagged `is_test_order = true` where the column exists.
- Preferred isolation: each test runs inside a transaction that is rolled back, so nothing persists. Where a test needs committed state (cron, concurrency), the script records every id it creates and a cleanup script removes exactly those rows.
- The 7 existing staging orders, 7 wallet transactions and 4 users are left alone unless the owner approves a reset. A snapshot of row counts is taken before and after every run.
- No fixture script is able to run against production: it checks the project marker first and aborts.

### 2.8 Payment-provider simulation

- **No test payment is made against Paystack or any live provider in this phase.**
- Stage 1 (database only): the evidence writer is exercised with synthetic provider responses supplied by the test harness under the staging writer role. This tests the database rules, not the provider.
- Stage 2 (webhook): a staging-only stub endpoint signs payloads with a staging-only signing secret and serves a fake "verify transaction" response. It can return success, wrong amount, wrong currency, pending, reversed and duplicate events.
- Stage 3 (provider test mode): Paystack test keys in the staging project only, when the owner approves. Separate decision.
- The stub and its secret never exist on production.

### 2.9 Logging and audit-data protection

- Staging logs follow the same rule as production is meant to: no phone numbers, no message bodies, no secrets, no full payloads. Hashes and ids only.
- Test data uses fake personal details, so a staging log leak exposes nothing real.
- Staging audit tables are not copied to production or to any shared location.
- Access to staging logs is limited to the same people as the staging project.

### 2.10 Verification that no production identifier remains

Checklist, all read-only, to be run after separation and before any extension is enabled:

1. No function body contains the production project reference.
2. No view, policy, trigger or default contains it (`pg_get_viewdef`, `pg_policies`, `pg_attrdef`).
3. No row in `app_config` or other configuration tables contains it.
4. Vault secret names listed; owner confirms values are staging-only.
5. Edge Function secrets listed by name in the dashboard; owner confirms none is a production value.
6. Storage bucket URLs in data rows do not point at production.
7. Frontend staging config points at staging.

---

## 3. Actions that need separate owner approval before staging changes

| #   | Action                                                                              | Type                    |
| --- | ----------------------------------------------------------------------------------- | ----------------------- |
| S1  | Replace hardcoded URLs in three staging functions                                   | Staging function change |
| S2  | Add staging configuration rows (`payments_live`, function base URL, project marker) | Staging data change     |
| S3  | Create staging secrets (owner enters values)                                        | Owner action            |
| S4  | Disable `trg_dispatch_notification` and cancel 14 pending notifications             | Staging change          |
| S5  | Create a migration history for staging                                              | Staging change          |
| S6  | Install `pgtap` in a dedicated schema                                               | Extension               |
| S7  | Apply the guard SQL draft to staging                                                | Migration               |
| S8  | Create test identities and fixtures                                                 | Staging data            |
| S9  | Install `pg_cron`; create jobs disabled                                             | Extension               |
| S10 | Install `pg_net` after verification 2.10                                            | Extension               |
| S11 | Deploy a payment stub and, later, WhatsApp functions to staging                     | Deployment              |
| S12 | Execute write tests                                                                 | Test execution          |
| S13 | Use Paystack test mode                                                              | Provider                |

None of these has been done.

---

## 4. Blockers

- Staging has no active admin and no second admin to approve one. Creating the first admin needs a privileged insert (S8).
- No Meta test number or email sandbox is known to exist for staging (owner to confirm).
- The origin of the existing staging data is not documented.
