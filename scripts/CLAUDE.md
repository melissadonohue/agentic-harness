# scripts/ — Script Conventions

This directory contains orchestration scripts that wrap deterministic workflows around agentic steps. Scripts are the harness's control plane — they set up environments, enforce preconditions, and clean up after agents.

## Key Scripts

- `dispatch.sh` — Orchestrates `/dispatch`: verifies preconditions, creates worktree, starts Docker container, seeds DB, hands off to agent, collects PR, triggers review, cleans up. (Phase 3)
- `bootstrap.sh` — Orchestrates `/bootstrap`: creates repo, deploys infrastructure, files product-level briefs as issues. (Phase 6)
- `seed.ts` — Database seeding for dispatch environments. Uses Faker with a fixed seed for deterministic, reproducible test data. (Phase 3)

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

### Testing

- Scripts are validated by running them. There are no unit tests for shell scripts.
- The dispatch script is tested by dispatching a small test issue and verifying the full lifecycle.
