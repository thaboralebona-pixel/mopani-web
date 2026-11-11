# ProjectX completion, evidence and handover prompt

Status: DRAFT for owner review. Documentation only. Dated 2026-11-10.
Use with: `PROJECTX-MASTER-OPERATING-INSTRUCTIONS.md`, which takes precedence over this prompt.

## Purpose

Produce an accurate, auditable record of the work actually performed. The record must be good enough that the next person can rely on it without repeating the work.

Creating documentation is not completing the wider ProjectX readiness programme. Never describe it that way.

## Reviewer rules

1. Report what happened, not what was intended.
2. Every claim has a label from the master instructions: VERIFIED, REPORTED, INFERRED or UNKNOWN.
3. Do not round up. A partial result is PARTIAL. An unverified result is NOT VERIFIED.
4. If a test was not run, write NOT RUN. Do not write "passed" for a test you did not run.
5. If a result was not established independently in this task, write NOT VERIFIED.
6. **Deployment evidence rule:** Never record a change as DEPLOYED unless the deployment action and its target environment are directly supported by inspected evidence. A commit, push, merge, deployment instruction or report from another person does not independently establish deployment. If deployment is only reported but cannot be verified, classify the claim as REPORTED and record the deployment status as NOT VERIFIED. Do not imply that the change is running in any environment.

## Required record

Fill in each section. Write "NONE" where nothing applies, and "UNKNOWN" where the answer is not known.

### 1. Task objective
One sentence stating the objective as the owner gave it, with the date.

### 2. Approved scope
- The categories permitted, each marked permitted or not permitted, and each with its own approval record:
  - Local repository and document inspection.
  - Local code changes.
  - Local tests.
  - Documentation changes.
  - Staging database reads.
  - Staging changes.
  - Production database reads.
  - Production changes.
- Read-only inspection must name where it occurred (local repository, staging database, or production database). Authorisation for one location is not authorisation for another.
- The written approval for each permitted category: who, when, and where it was given.
- Any approval that does not meet the owner approval standard in the master instructions, section 3.5, is marked REPORTED.

### 3. Actual work performed
A numbered list. Each item is one action, in the order it happened, with its date, its evidence label and, for any change, its approval and execution status (for example: "Read `docs/pilot/OWNER-DECISIONS.md` at commit `521e4d6`. VERIFIED.").

### 4. Files created or modified
For each file: path, whether it was created or modified, its size or the number of lines changed, and the commit that includes it. Use the terms exactly:
- **Created:** the file did not exist before.
- **Modified:** the file existed and its content changed.
- **Reviewed:** the file was read, but not changed.

### 5. Git branch and commit
- Repository: owner and name.
- Branch name.
- Commit hash, message and date.
- Whether the commit was pushed, with the remote head hash confirmed by `git ls-remote`.
- Whether the branch was merged. If merging was not asked for, state NOT MERGED.

### 6. Tests actually executed
For each test: name, the command or method, and status (RUN or NOT RUN). If a test was not run, say why.

### 7. Exact test results
For each RUN test: the exact result as printed, including the count of passed and failed items, and any error text. Do not summarise away failures.

### 8. Evidence inspected
A list of every source inspected: file path and line range, commit hash, query text and output summary, document and section, date and time of inspection. Keep raw outputs in a referenced file where they are long.

### 9. Findings discovered
Each finding with ID, severity, and its confirmation status (CONFIRMED, PLAUSIBLE or UNPROVEN), as defined in the independent audit prompt.

Each finding also states:
- Its evidence classification (VERIFIED, REPORTED, INFERRED or UNKNOWN).
- Where it proposes a corrective action, that action's approval status (APPROVED or NOT APPROVED) and execution status (EXECUTED or NOT EXECUTED), as defined in master section 4, B and C. Report the actual position; do not assume a value.

### 10. Changes not performed
Every change that was proposed, requested or considered but not made. For each, state why: not approved, not in scope, blocked, or deferred.

### 11. Outstanding unknowns
Each question the work did not answer, and what evidence would answer it.

### 12. Remaining risks
Each risk, with its severity and whether it is an inference or a confirmed fact.

### 13. Acceptance criteria
Each criterion from the brief, marked MET or UNMET, with the evidence that supports the mark. A criterion without evidence is UNMET.

### 14. Owner decisions required
Each decision the owner must make before the next step, stated as a question with the options.

### 15. Recommended next action
One action, the smallest safe one, with the approval it needs.

## Terminology

These terms are distinct. Do not use one for another.

| Term | Meaning | Not the same as |
|---|---|---|
| **Created** | A new file or object now exists. | Reviewed |
| **Modified** | An existing file or object was changed. | Created |
| **Reviewed** | Read and assessed. Nothing was changed by the review. | Tested |
| **Tested** | A test was run and its output was inspected. | Reviewed |
| **Committed** | A commit exists in the local repository. | Pushed |
| **Pushed** | The commit exists on the remote branch. Confirm with `git ls-remote`. | Merged |
| **Merged** | The change is part of the target branch. | Pushed |
| **Deployed** | The change is running in an environment. | Merged |
| **Verified in the target environment** | Checked in the environment it is meant for, with evidence from that environment. | Tested locally |

Status words used in the record:
- **NOT RUN.** A test or check was not executed.
- **NOT VERIFIED.** A result was not independently established in this task.

## Final status

Choose exactly one:

- **COMPLETE.** Every acceptance criterion is met, with evidence. Nothing is outstanding.
- **PARTIAL.** Some work is complete. At least one item or criterion remains open.
- **BLOCKED.** The work cannot proceed within the current permissions or evidence. State the blocker.
- **NOT STARTED.** No substantive work was performed.

If any acceptance criterion is unmet, the status cannot be COMPLETE.

## Handover

The handover is written for a person who did not do the work.

### What the next person can safely do
A list of actions that are within approved scope, with the evidence they need before starting.

### What remains prohibited
A list of actions that are not approved, with the reason and the approval that would be needed.

### What evidence is still needed
Each evidence request, what it would prove, and who holds it.

### Which decisions require owner approval
Each decision, stated as a question, with the options and the recommended option.

## Required closing statement

End every record with this statement, filled in:

> This record covers [task name] as at [date and time, SAST and UTC]. Status: [COMPLETE / PARTIAL / BLOCKED / NOT STARTED]. Creating documentation has not completed the wider ProjectX readiness programme. No production or staging change was made unless listed under section 3, and each such change is listed with its approval.
