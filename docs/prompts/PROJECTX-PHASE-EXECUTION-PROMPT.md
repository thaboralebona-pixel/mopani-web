# ProjectX phase execution prompt

Status: DRAFT for owner review. Documentation only. Dated 2026-11-10.
Use with: `PROJECTX-MASTER-OPERATING-INSTRUCTIONS.md`. That document takes precedence over this one.

## How to use
Paste this prompt with a completed phase brief. The brief must name the phase, the objective, the permitted categories and the acceptance criteria. If any of these is missing, stop and ask.

## Instructions to Claude

Execute one narrowly scoped project phase. Work only within the authorised boundaries of the brief.

### Step 1: Identify the task
State the phase name, its objective, and the single outcome it must produce.

### Step 2: Read the project documentation first
Read the relevant documents before doing anything else. At minimum:
- The master operating instructions.
- The owner decisions register (`docs/pilot/OWNER-DECISIONS.md`).
- The security register (`docs/pilot/SECURITY-REGISTER.md`) for any finding this phase touches.
- The most recent phase documents for the area.

Record which documents you read and their last commit.

### Step 3: Establish the permitted scope
Classify every intended action into one of these categories. Each is a separate permission. Permission for one category is never permission for another.

| Category | Examples | Default status |
|---|---|---|
| Read-only inspection | Reading repository files; reading documents | Permitted only if in brief |
| Documentation changes | Editing or creating files under `docs/` | Permitted only if in brief |
| Local code changes | Editing application code | Permitted only if in brief |
| Local tests | Running `npm run check` and unit tests | Permitted only if in brief |
| Staging changes | Any change to the staging project | Not permitted unless separately approved in writing |
| Production changes | Any change to production | Not permitted unless separately approved in writing |
| Production or staging reads | Any database query | Not permitted unless separately approved in writing |

### Step 4: Identify prohibited actions
List the prohibited actions for this phase from the master instructions and the brief. Include, at minimum, anything that touches production or staging databases, payments, cron jobs, grants, functions, deployments, merges or secrets.

### Step 5: List dependencies and assumptions
For each dependency (a document, a commit, an approval, an external fact), state whether it is VERIFIED, REPORTED, INFERRED or UNKNOWN. For each assumption, state what changes if it is wrong.

### Step 6: Define measurable acceptance criteria
Write each criterion as a yes-or-no test with the evidence that will show it. Example: "Every wallet-writing function is listed with its ACL. Evidence: the query output or the repository file it came from." Vague criteria such as "reviewed" are not acceptable.

### Step 7: Work only within authorised boundaries
- Do the work in the permitted categories only.
- If you find a need outside the scope, record it as an outstanding item. Do not act on it.
- Keep unrelated work out of scope, even when it looks easy or useful.

### Step 8: Record evidence and results
- For each finding, record the evidence: file path and line, commit hash, command run and its output, or query text and its output.
- Do not summarise a result you have not inspected.
- Keep raw outputs in a referenced file when they are long.

### Step 9: Stop at an approval gate
Stop when:
- The next step needs an approval not in the brief.
- A stop condition in the master instructions applies.
- The acceptance criteria are met or cannot be met within scope.

Do not continue into the next phase on your own initiative.

## Required end-of-phase report

Every phase ends with these six headings, in this order:

1. **Work completed.** Each item, with its evidence label.
2. **Work not completed.** Each item, with the reason.
3. **Evidence.** File paths, commit hashes, command outputs, query outputs and dates.
4. **Outstanding risks.** Each risk, with its severity and whether it is an inference or a confirmed fact.
5. **Acceptance criteria.** Each criterion marked MET or UNMET, with the evidence that supports the mark.
6. **Approval required for the next phase.** State exactly what approval is needed and from whom. Do not describe an approval as given unless it meets the owner approval standard in the master instructions, section 3.5.

Each work item also records its approval status (APPROVED or NOT APPROVED) and its execution status (EXECUTED or NOT EXECUTED), as defined in master section 4, B and C. Report the actual position for each item; do not assume a value.

## Repository and local checks

- Before any repository claim, state the branch, the HEAD commit and the remote URL you inspected.
- Run `npm run check` only when the brief permits local tests. Report the actual result, including failures.
- A passing local check does not show that the database is secure or that financial controls work.

## Prohibited in all phases unless separately approved in writing

- Production database queries, connections or access.
- Staging writes, migrations, fixtures or configuration changes.
- Grants, revocations, role creation or function changes.
- Cron changes.
- Edge Function deployments.
- Payment activation or Paystack configuration.
- Historical wallet or ledger adjustments.
- Changes to order 96 or dispute 9.
- Merges to main.
- Use or storage of any credential in chat, a file or the repository.
