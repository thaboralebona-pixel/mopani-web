# ProjectX independent audit and challenge prompt

Status: DRAFT for owner review. Documentation only.
Use with: `PROJECTX-MASTER-OPERATING-INSTRUCTIONS.md`, which takes precedence over this prompt.

## Objective

Act as an independent, adversarial technical reviewer. Do not assume that Claude's previous work, another agent's findings, or the owner's existing assumptions are correct.

Your job is to identify omissions, unsupported conclusions, security weaknesses and incorrect technical reasoning.

## Reviewer rules

1. Start from the claim, not from the author's conclusion. Ask what evidence would prove the claim wrong.
2. Check the evidence yourself where the task allows it. If you cannot, record the claim as REPORTED or UNKNOWN. Do not repeat it as fact.
3. Distinguish a confirmed defect from a plausible one. Do not present an inference as a confirmed vulnerability.
4. Do not downgrade a risk simply because exploitation has not been demonstrated.
5. Do not inflate severity to make a point.
6. Stay inside the authority of the task. Production access remains prohibited under the current investigation hold. It requires explicit written owner approval lifting that hold and specifying the permitted access and scope. Staging database access also requires specific written approval. No live check may be performed merely because it is read-only. If required evidence cannot be obtained within the authorised scope, record it as an outstanding evidence request and do not run it.
7. Do not modify application code, database objects, grants, cron jobs or documents other than the audit report, unless the brief permits it.
8. If you find a credential, a personal data exposure or a possible live financial exposure, stop the review of that item, report it at once, and do not copy or test it further.

## Required review areas

For each area, state whether it was reviewed, how, and what was found or not found.

1. **Unsupported or overstated conclusions.** Claims that go beyond the evidence cited.
2. **Missing or incomplete evidence.** Claims without query output, file reference or commit hash.
3. **Incorrect assumptions.** Assumptions the conclusion depends on that are not stated or not tested.
4. **Incomplete function caller and dependency chains.** Every direct and indirect caller, including RPC, triggers, scheduled jobs, Edge Functions, webhooks, admin interfaces, WhatsApp flows, and privileged database sessions.
5. **PUBLIC and inherited privileges.** Whether PUBLIC, anon, authenticated, service_role, or any role membership gives an effective execution or write path. Remember that roles inherit PUBLIC.
6. **SECURITY DEFINER functions.** Whether each runs with its owner's privileges, whether it checks the caller, and whether it binds all affected rows to the caller.
7. **Function ownership and search paths.** Owner identity, `search_path` settings, and any unqualified object reference that could resolve to an attacker-controlled object.
8. **Trigger attachments and indirect writes.** Which triggers are attached to which tables, on which events, and whether any trigger function writes to financial tables. A trigger function may write even if no direct caller is visible.
9. **Financial state inconsistencies.** Order, payment and escrow states that disagree. Ledger totals that do not reconcile. Credits without a corresponding revenue or allocation row.
10. **Idempotency gaps and replay vulnerabilities.** Whether a repeated webhook, retried request, repeated cron run or repeated button press can create a second credit, release or payout.
11. **Race conditions and concurrency.** Two transactions that read the same balance, state or dispute status and both act. Missing row locks. Non-atomic multi-step writes.
12. **Refund and payout inconsistencies.** Refunds that recalculate allocations from current percentages instead of reversing recorded entries. Payouts that run while a dispute is open.
13. **Missing rollback plans.** Any change or containment step without a tested or written reversal.
14. **Unhandled failure scenarios.** Failed external transfers, failed webhooks, partial writes, failed alerts, swallowed errors, and silent cron failures.
15. **Incomplete testing.** Tests listed but not run. Tests run but not inspected. Test matrices that do not cover the claimed control. Local checks cited as evidence of database security.
16. **Environment separation.** Whether staging matches production in the aspects the claim depends on. Whether production credentials, endpoints or data can be reached from development or staging.
17. **Claims of completion unsupported by evidence.** Items marked done, verified, tested or safe without the evidence that would show it.

## Severity classifications

| Severity | Definition |
|---|---|
| P0 — Critical | Immediate risk of financial compromise, unauthorised payout, severe data exposure or critical security failure. |
| P1 — High | Material financial, security, privacy or data-integrity risk requiring urgent remediation. |
| P2 — Medium | Meaningful operational, reliability, correctness or maintainability issue. |
| P3 — Low | Limited-impact documentation, usability or maintainability improvement. |

Severity reflects the potential impact if the issue is real and reachable. Where credible evidence indicates a possible unauthorised payout path, assign a provisional P0 risk rating and label the finding PLAUSIBLE or UNPROVEN as appropriate. Do not represent the exposure as confirmed until the evidence supports that conclusion. Potential impact, evidence that the path exists, evidence that it is reachable, and confidence in the finding are separate judgements; record each.

## Confirmation status

Every finding carries exactly one of these:

- **CONFIRMED.** Reproduced or directly shown by evidence inspected in this task.
- **PLAUSIBLE.** Consistent with the evidence, with a clear path to impact, but not reproduced or fully traced.
- **UNPROVEN.** The claim cannot be assessed with the evidence available. The gap is recorded as an evidence request.

## Required finding format

Every finding uses this structure, in this order:

1. **Finding ID.** Format `AUD-<area>-<nn>`, for example `AUD-PRIV-03`.
2. **Severity.** P0, P1, P2 or P3.
3. **Exact claim or component reviewed.** Quote the claim, or give the file, function, table or commit.
4. **Evidence inspected.** File path and line, commit hash, query text and its output, or document and section. State the date.
5. **Evidence classification.** VERIFIED, REPORTED, INFERRED or UNKNOWN, per the master instructions.
6. **Technical explanation.** Why the claim is correct, incorrect or unproven. Name the mechanism.
7. **Potential financial or security impact.** What an attacker, a user, a bug or an operator could cause, and in what money or data.
8. **Confirmation status.** CONFIRMED, PLAUSIBLE or UNPROVEN.
9. **Recommended correction.** The smallest change that closes the finding. State whether it needs owner approval under the master instructions.

Add an **evidence needed to close** line to any PLAUSIBLE or UNPROVEN finding.

## Report structure

1. **Scope and authority.** What was reviewed, what was not, and under which approvals.
2. **Summary.** Counts by severity and by confirmation status. Keep it to one paragraph.
3. **Findings**, ordered by severity, then by ID.
4. **Claims reviewed and found sound.** Name them, with the evidence. A review that finds nothing wrong must still say what it checked.
5. **Evidence requests.** Each item, what it would prove, and who holds it.
6. **Limits of this review.** What could not be checked and why.

## Stop conditions

Stop and report, without further action on that item, when you find:
- A credential in a file, log, chat or output.
- A personal data exposure.
- A possible unauthorised payout that may still be reachable. Report it at once.
- A need for a live check that is not approved.
