# scripts/ — Script Conventions

This directory contains orchestration scripts that wrap deterministic workflows around agentic steps. Scripts are the harness's control plane — they set up environments, enforce preconditions, and clean up after agents.

## Key Scripts

### dispatch.sh — Dispatch Orchestrator

Orchestrates `/dispatch <issue-number>`: the core primitive for isolated agent execution.

**Usage**:

```bash
scripts/dispatch.sh <issue-number> [--keep]
```

**What it does**, in order:

1. Validates the issue exists and is labeled `ready-for-agent`.
2. Checks the issue has no `blocked` label.
3. Reads the issue title and body via `gh`.
4. Creates a fresh git worktree from `origin/main` at `.worktrees/issue-<number>`.
5. Creates a branch named `issue-<number>/<slug-from-title>`.
6. Ensures Postgres is running via Docker Compose.
7. Creates a dispatch-specific database `dispatch_<issue_number>`.
8. Runs migrations and seeds the database via `seed.ts`.
9. Starts a Docker container `dispatch-<issue-number>` with the worktree mounted.
10. Posts an initial checkpoint comment on the issue.
11. Invokes Claude Code with the issue body as the task and CLAUDE.md tree as context.
12. Runs a CI budget loop — up to N rounds (default: 5) of push → CI check → fix.
13. Creates a PR linked to the issue.
14. Posts a completion checkpoint comment.
15. Triggers `/review` via `review.sh`.
16. Cleans up worktree, container, and database on exit (via `trap`).

**Flags**:

- `--keep` — Skip cleanup on exit. Leaves the worktree, container, and database in place for debugging.

**Environment variables**:

- `GITHUB_TOKEN` — Required for `gh` CLI operations.
- `CI_BUDGET` — Override the default CI budget (default: 5).
- `DISPATCH_DRY_RUN=1` — Skip Claude Code invocation (for testing the orchestration flow).

**CI budget**: The default is 5 rounds. Override per-issue by adding a `ci-budget:N` label to the issue. After exhausting the budget without a passing PR, the script posts an escalation comment and labels the issue `escalated`.

**Checkpointing**: The script posts structured progress comments on the issue at key milestones: environment creation, completion, escalation. Comments include status, CI round count, what was done, and what remains.

**Concurrency safety**: The script checks for existing worktrees and containers before creating new ones. Two concurrent dispatches for different issues do not interfere. Two dispatches for the same issue are blocked.

### seed.ts — Database Seeder

Produces deterministic, reproducible test data for dispatch environments using `@faker-js/faker` with a fixed seed (`42`).

**Usage**:

```bash
DATABASE_URL=postgresql://... npx tsx scripts/seed.ts
```

**What it does**:

1. Connects to the database specified by `DATABASE_URL`.
2. Checks which tables exist in the public schema.
3. If no tables exist (schema is stubbed), exits gracefully.
4. Generates deterministic data: 5 users (1 admin, 4 members), 3 projects.
5. Truncates existing data and inserts fresh seed data.
6. Prints a seed manifest (JSON) showing what was inserted.

**Determinism**: Uses faker seed `42`. Every run produces identical data — same UUIDs, same emails, same names. This makes test assertions stable across environments.

**Extensibility**: As new entities are added to the schema, add corresponding generator functions and seeding logic. Follow the existing pattern: generate with faker, check if table exists, truncate, insert.

### review.sh — Review Orchestrator

Orchestrates `/review <pr-number>`: the agent-to-agent review pipeline. A separate Claude Code session (fresh, no authoring memory) evaluates the PR against the linked issue spec, codebase conventions, and quality criteria.

**Usage**:

```bash
scripts/review.sh <pr-number> [--budget N]
```

**What it does**, in order:

1. Reads PR metadata: title, body, diff, branch, changed files.
2. Extracts the linked issue number from `closingIssuesReferences` or PR body (`Closes #N`).
3. Reads the linked issue body (the spec the PR should resolve).
4. Gathers relevant CLAUDE.md files by walking up directories from each changed file.
5. Gathers transitive dependencies (one level) — files imported by changed files.
6. Enters the multi-pass review loop (up to N rounds, default: 5):
   a. Invokes a **fresh** Claude Code session as the reviewer.
   b. Reviewer evaluates: correctness, conventions, tests, types, accessibility.
   c. Reviewer outputs a structured review with `REVIEW_STATUS: APPROVED | CHANGES_REQUESTED`.
   d. Posts the review as a structured PR comment.
   e. If approved → exits successfully.
   f. If changes requested → creates a review worktree, invokes a separate Claude Code session as the author to fix issues, pushes fixes, cleans up worktree, loops.
7. If the budget is exhausted without approval, posts an escalation comment and labels the PR `escalated`.

**Flags**:

- `--budget N` — Override the review retry limit (default: 5).

**Environment variables**:

- `GITHUB_TOKEN` — Required for `gh` CLI operations.
- `REVIEW_BUDGET` — Override the default review budget (default: 5).
- `REVIEW_DRY_RUN=1` — Skip Claude Code invocations (for testing the orchestration flow).

**Review criteria**: correctness (does PR resolve the issue?), conventions (CLAUDE.md compliance), tests (sufficient and meaningful?), types (precise, no `any`?), accessibility (AA standard for UI changes).

**Multi-pass protocol**: Each review round is posted as a structured PR comment with: approval status, issues found, issues resolved since last review, remaining concerns. The author agent receives review feedback and pushes fixes to the same branch.

**Escalation**: When the review budget is exhausted, the script posts a summary of all unresolved concerns and labels the PR `escalated`. The PR stays open for human review.

**Separation of concerns**: The reviewer is always a fresh Claude Code session. It has no memory of the authoring process — it evaluates output, not reasoning. The author revision agent is also a separate session, but receives the review feedback as input.

**Integration with dispatch**: `dispatch.sh` calls `review.sh` automatically after producing a PR. The review budget matches the CI budget by default.

### triage.sh — Triage Orchestrator

Orchestrates `/triage <issue-number>`: the two-tier intake and readiness system. Bridges product-level briefs to dispatch-ready implementation issues.

**Usage**:

```bash
scripts/triage.sh <issue-number> [--approve]
```

**What it does** — Two tiers plus an approval handler:

**Tier 1 — Intake** (triggered when issue is labeled `product-brief` or auto-detected as product-level language):

1. Reads the product brief from the issue body.
2. Gathers codebase context: all CLAUDE.md convention docs, schema files, route structure, seam interfaces.
3. Invokes Claude Code as the intake agent to propose a decomposition.
4. The decomposition lists each proposed child issue with: convention reference, summary, dependencies, key parameters, and Definition of Done.
5. Posts the decomposition as a structured comment on the brief issue.
6. Removes `needs-triage` label if present. Awaits human approval.

**Tier 2 — Readiness** (triggered when issue is implementation-level):

1. Detects relevant CLAUDE.md conventions based on issue keywords.
2. Invokes Claude Code as a readiness evaluator.
3. Evaluates: scope clarity, convention mapping, key parameters, dependencies, Definition of Done.
4. Outputs one of three statuses:
   - `READY` → labels the issue `ready-for-agent` (triggers dispatch-on-label).
   - `NEEDS_DETAIL` → flags specific missing inputs in a comment, labels `needs-triage`.
   - `NEEDS_BREAKDOWN` → proposes sub-issues in a comment, labels `needs-triage`.

**Approval handler** (`--approve`):

1. Reads the most recent decomposition comment on a `product-brief` issue.
2. Parses each `### Issue N:` block from the decomposition.
3. Creates child issues via `gh issue create`, with parent brief link and full implementation details.
4. Labels dependency-free issues `ready-for-agent`; labels dependent issues `blocked`.
5. Posts a summary comment listing all created child issues.
6. Adds `decomposition-approved` label to the parent brief.

**Flags**:

- `--approve` — Create child issues from an approved decomposition instead of running triage.

**Environment variables**:

- `GITHUB_TOKEN` — Required for `gh` CLI operations.
- `TRIAGE_DRY_RUN=1` — Skip Claude Code invocations (for testing the orchestration flow).

**Auto-detection**: If no `product-brief` label is present, the script auto-detects product-level language using signal scoring. Product signals: user outcome language ("users need", "ability to", "so that"). Implementation signals: file paths, code references, import/export statements. If product signals >= 2 and implementation signals < 2, the issue is treated as a product brief (Tier 1). Otherwise, Tier 2.

**GitHub Actions integration**: `.github/workflows/triage-on-label.yml` triggers triage when an issue is labeled `product-brief` or `needs-triage`. The workflow also handles approval — when a comment starting with "approved" is posted on a `product-brief` issue, or when the `decomposition-approved` label is added, it runs `triage.sh --approve` to create child issues.

### bootstrap.sh — Bootstrap Orchestrator (Phase 6)

Not yet implemented. Will orchestrate `/bootstrap`: create repo, deploy infrastructure, file product-level briefs as issues.

## Conventions

### Language

- Shell scripts (`.sh`) for orchestration that sequences git, Docker, and GitHub CLI commands. Shell is the most deterministic wrapper available.
- TypeScript (`.ts`) for scripts that need structured data manipulation (seeding, report generation).

### Style

- All shell scripts must use `set -euo pipefail` at the top.
- Shell scripts that create environments (worktrees, containers, databases) must use a cleanup trap (`trap cleanup EXIT`) to prevent orphaned resources. Scripts that only read and post comments (like `triage.sh`) do not need a cleanup trap.
- All shell scripts must be executable (`chmod +x`).
- Use descriptive function names. The script reads like a procedure, not a code golf entry.

### Error Handling

- Scripts fail loudly. No silent failures, no swallowed exit codes.
- On failure, the cleanup trap runs, and the script posts an escalation comment on the relevant issue (if applicable).
- Seed script exits gracefully when schema is stubbed (no tables exist).

### Testing

- Scripts are validated by running them. There are no unit tests for shell scripts.
- The dispatch script is tested by dispatching a small test issue and verifying the full lifecycle.
- The triage script is tested by triaging a product brief and an implementation issue.
- Use `DISPATCH_DRY_RUN=1` to test the dispatch orchestration without invoking Claude Code.
- Use `TRIAGE_DRY_RUN=1` to test the triage orchestration without invoking Claude Code.
- Use `REVIEW_DRY_RUN=1` to test the review orchestration without invoking Claude Code.
