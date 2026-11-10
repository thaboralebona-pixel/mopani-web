# ProjectX change proposal and SQL review prompt

Status: DRAFT for owner review. Documentation only.
Use with: `PROJECTX-MASTER-OPERATING-INSTRUCTIONS.md`, which takes precedence over this prompt.

## Purpose

Independently review a proposed technical change before anyone implements it. The review answers whether the change is safe to put in front of the owner. It does not approve or execute the change.

A technical recommendation is never owner approval or execution authority.

## Reviewer rules

1. Review the proposal as written. Do not fill gaps with what you think the author meant. Record each gap.
2. Do not run the change, any part of it, or any test that writes, in any environment, unless the brief permits it in writing.
3. Obtain the current definitions of every object the change touches only from sources authorised for the task. Do not connect to production or staging to obtain them unless the owner has separately authorised that specific access. If a current definition cannot be established from authorised evidence, mark it UNKNOWN and identify the evidence required. Do not rely on the proposal's description of them.
4. Classify every statement about the current system using the master instructions' labels.

## 1. Change description

Answer each question. Write "UNKNOWN" where the proposal does not say.

- What is changing?
- Why is it necessary? Which finding, incident or requirement does it address?
- Which components and database objects are affected? List tables, views, functions, triggers, policies, grants, cron jobs, Edge Functions, and client code.
- What existing behaviour changes? State it for each caller and each role.
- What is the intended final state? Describe it so that it can be checked.

## 2. Security

For each object in scope, establish the effective privilege, not only the stated one.

- **Effective privileges.** Grants to each role, including inherited ones.
- **RLS.** Whether RLS is enabled, whether it is forced, which policies apply, and whether any policy depends on a function that is itself exposed.
- **PUBLIC and inherited permissions.** Every role inherits PUBLIC. A grant to PUBLIC is a grant to every role, including any new role.
- **Role memberships.** Direct and indirect. Confirm that no change adds a membership to a privileged role.
- **SECURITY DEFINER functions.** Whether the function runs with its owner's rights, whether it checks the caller, and whether it binds all rows to the caller.
- **Function ownership and search paths.** Owner identity. `search_path` set on the function. Unqualified references that could resolve to an object an attacker controls.
- **Trigger implications.** Any trigger the change creates, alters or enables, and any trigger attached to an object it touches. A trigger can write even when no caller is visible.
- **Service-role exposure.** Whether the change widens what service_role can reach. Service_role bypasses RLS.
- **Direct and indirect execution paths.** Every path to each changed function: direct RPC, another function, a trigger, a cron job, an Edge Function, or an administrative interface.
- **Default privileges.** Whether the change alters `ALTER DEFAULT PRIVILEGES` behaviour, so that future objects inherit a broader grant.

## 3. Financial integrity

- **Integer minor-unit calculations.** Every amount is an integer count of minor units. Check for division, rounding, and floating-point arithmetic.
- **Order, payment and escrow state separation.** The change must not merge these states or let one imply another. An order's escrow status is not proof of receipt.
- **Payment verification.** Any payment-driven transition must rest on verified provider evidence: raw-body signature check, direct API verification, matching reference, amount, currency, and buyer and order consistency.
- **Idempotency.** Repeated calls, retries and duplicate events produce the same result as one call, with no second credit, release or payout.
- **Duplicate processing.** Two copies of the same event, submitted at the same time, must not both succeed.
- **Race conditions.** Two transactions reading and acting on the same state. Row locks, unique constraints or serialisation must prevent double action.
- **Payout allocations.** Each payout leg has an explicit recipient. A missing recipient is held in an explicitly recorded suspense arrangement, not redirected.
- **Refund behaviour.** A refund reverses the recorded allocation entries. It does not recalculate allocations from current percentages.
- **Financial history preservation.** No cascading deletion of financial records. Corrections are new entries, not edits or deletes.
- **External transfer failures.** Failed external transfers are recorded in a durable status history. A failed transfer does not leave an internal entry that looks like a completed payout.
- **Reconciliation.** After the change, the ledger must still reconcile to revenue, allocations and external settlement. State the reconciliation query that will show it.

## 4. Data integrity

- **Foreign keys.** New or changed foreign keys: their target, their delete behaviour, and whether existing rows satisfy them.
- **Unique constraints.** Every constraint that protects an identity or an idempotency key. Confirm it exists and is enforced.
- **Check constraints.** Non-negative amounts, valid state values, and allocation totals that match their parent.
- **Nullability.** Whether a new column can be null, and what a null means for each reader.
- **Referential integrity.** Whether any row can point at a missing parent after the change.
- **Deletion behaviour.** `ON DELETE` actions. Financial records must not cascade.
- **Historical data compatibility.** Whether existing rows satisfy the new constraints. Whether existing code paths still work with existing rows. Whether old test-era records are excluded or flagged.
- **Concurrency.** Whether the change introduces a lock, a long transaction or a new write path that conflicts with existing ones.

## 5. Operational safety

- **Dependencies.** Every object that must exist first, and every object that depends on something the change alters.
- **Execution order.** The exact order of statements. State what happens if the change stops partway.
- **Migration safety.** Whether the change can run in one transaction, whether it rewrites a large table, and whether it needs a maintenance window.
- **Locking.** Which locks it takes, on which objects, and for how long. Check for `ACCESS EXCLUSIVE` on a live table.
- **Rollback feasibility.** Covered in section 7.
- **Monitoring.** How the owner will know the change is working, and how a failure would show. Name the signal, not only the intent.
- **Failure recovery.** What to do if the change fails half way, and what state the database is left in.
- **Environment separation.** Whether the change is written for one environment and would behave differently in another. State the staging and production differences that matter. Confirm the change does not connect production from a non-production context.

## 6. Testing requirements

Specify tests in each category below. For each test, state whether it is PROPOSED, RUN, or NOT RUN. Only RUN tests can be reported as tested, and only with their output inspected.

| Category | What it must prove |
|---|---|
| Positive | The intended behaviour works for a valid input. |
| Negative | Each prohibited input or action fails, with the expected error. |
| Permission | Each role can do what it should and nothing more. Test as the real roles, not as postgres. |
| Idempotency | A repeated call or event does not create a second effect. |
| Concurrency | Two simultaneous calls on the same object produce one effect. |
| Failure | A forced failure part way through leaves no partial effect. |
| Regression | Existing behaviour that the change must not alter still works. |
| Financial reconciliation | Totals agree before and after, and the reconciliation query returns zero variance. |

Staging tests that write are not run without written approval. Production tests that write are not run at all unless the owner approves them in writing.

## 7. Rollback

Review whether rollback is genuinely safe.

- Describe the exact rollback statements, and check that each one can be run.
- Check that the rollback restores the intended prior state, not a state that was already unsafe.
- Never recommend restoring a historical configuration blindly. A historical grant, a historical cron job or a historical function can re-enable an unsafe payout path.
- Where a rollback would re-enable a payout path, the rollback must be blocked or must require a separate approval.
- If rollback cannot be fully tested, say so and state what is unknown.
- Rollback of data is not always possible. Where a data change is not reversible, say so and require the change to be approved on that basis.

## 8. Required output

The review ends with these sections, in order.

1. **Summary.** The change, in one paragraph, and its reviewed status.
2. **Findings.** Each finding with its ID, severity (P0 to P3), evidence, classification (VERIFIED, REPORTED, INFERRED or UNKNOWN), and required correction. Use the same format as the independent audit prompt.
3. **Gaps in the proposal.** Each unanswered question from section 1, and each unstated assumption.
4. **Tests.** Each test in section 6 with its status: PROPOSED, RUN or NOT RUN. Results only for RUN tests.
5. **Rollback assessment.**
6. **Final recommendation.** Exactly one of:
   - **APPROVE FOR OWNER CONSIDERATION.** The proposal is technically sound on the evidence reviewed. The owner must still decide whether to approve it.
   - **CONDITIONAL — REQUIRED CHANGES.** The proposal can be made acceptable with the listed changes. Name them.
   - **REJECT.** The proposal is unsafe or wrong as written.
   - **INSUFFICIENT EVIDENCE.** The proposal cannot be assessed. Name the evidence that is missing.
7. **Owner decisions still required.** Every decision that the recommendation does not settle.

Do not write "approved", "safe to deploy" or "ready to run". Those words are owner decisions, not review outcomes.
