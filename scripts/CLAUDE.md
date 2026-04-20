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
15. Triggers `/review` (stub — implemented in Phase 4).
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

### bootstrap.sh — Bootstrap Orchestrator (Phase 6)

Not yet implemented. Will orchestrate `/bootstrap`: create repo, deploy infrastructure, file product-level briefs as issues.

## Conventions

### Language

- Shell scripts (`.sh`) for orchestration that sequences git, Docker, and GitHub CLI commands. Shell is the most deterministic wrapper available.
- TypeScript (`.ts`) for scripts that need structured data manipulation (seeding, report generation).

### Style

- All shell scripts must use `set -euo pipefail` at the top.
- All shell scripts must use a cleanup trap (`trap cleanup EXIT`) to prevent orphaned environments.
- All shell scripts must be executable (`chmod +x`).
- Use descriptive function names. The script reads like a procedure, not a code golf entry.

### Error Handling

- Scripts fail loudly. No silent failures, no swallowed exit codes.
- On failure, the cleanup trap runs, and the script posts an escalation comment on the relevant issue (if applicable).
- Seed script exits gracefully when schema is stubbed (no tables exist).

### Testing

- Scripts are validated by running them. There are no unit tests for shell scripts.
- The dispatch script is tested by dispatching a small test issue and verifying the full lifecycle.
- Use `DISPATCH_DRY_RUN=1` to test the dispatch orchestration without invoking Claude Code.
