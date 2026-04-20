#!/usr/bin/env bash
# =============================================================================
# Agentic Harness — Dispatch Orchestrator
# =============================================================================
# Usage: scripts/dispatch.sh <issue-number> [--keep]
#
# Orchestrates /dispatch: validates preconditions, creates an isolated worktree,
# starts a Docker container, seeds the database, hands off to Claude Code,
# collects the PR, links it to the issue, triggers review, and cleans up.
#
# Flags:
#   --keep    Skip cleanup on exit (for debugging)
#
# Environment:
#   GITHUB_TOKEN        Required for gh CLI operations
#   CI_BUDGET           Override default CI budget (default: 5)
#   DATABASE_URL        Base Postgres connection (default: from .env.example)
#   DISPATCH_DRY_RUN    If set to "1", skip Claude Code invocation (for testing)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_BASE="${REPO_ROOT}/.worktrees"
DOCKER_COMPOSE_FILE="${REPO_ROOT}/docker/docker-compose.yml"
DOCKERFILE_DEV="${REPO_ROOT}/docker/Dockerfile.dev"
DEFAULT_CI_BUDGET=5
SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: ${SCRIPT_NAME} <issue-number> [--keep]"
  echo ""
  echo "  issue-number   GitHub issue number to dispatch"
  echo "  --keep         Skip cleanup on exit (for debugging)"
  exit 1
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  echo "[dispatch] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_error() {
  echo "[dispatch] $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ISSUE_NUMBER=""
KEEP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [[ -z "${ISSUE_NUMBER}" ]]; then
        ISSUE_NUMBER="$1"
      else
        log_error "Unexpected argument: $1"
        usage
      fi
      shift
      ;;
  esac
done

if [[ -z "${ISSUE_NUMBER}" ]]; then
  log_error "Missing required argument: issue-number"
  usage
fi

# Validate issue number is numeric
if ! [[ "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
  log_error "Issue number must be numeric, got: ${ISSUE_NUMBER}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Derived names
# ---------------------------------------------------------------------------
WORKTREE_DIR="${WORKTREE_BASE}/issue-${ISSUE_NUMBER}"
CONTAINER_NAME="dispatch-${ISSUE_NUMBER}"
DB_NAME="dispatch_${ISSUE_NUMBER}"
BRANCH_NAME=""  # Set after reading the issue title
CI_ROUND=0
PR_URL=""

# CI budget: check for ci-budget:N label, fall back to env var, then default
CI_BUDGET="${CI_BUDGET:-${DEFAULT_CI_BUDGET}}"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
  local exit_code=$?

  if [[ "${KEEP}" == true ]]; then
    log "--keep flag set. Skipping cleanup."
    log "  Worktree: ${WORKTREE_DIR}"
    log "  Container: ${CONTAINER_NAME}"
    log "  Database: ${DB_NAME}"
    return
  fi

  log "Cleaning up..."

  # Stop and remove Docker container
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
    log "  Removing container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi

  # Drop the dispatch database
  if docker exec harness-postgres psql -U harness -d harness_dev -tc \
    "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" 2>/dev/null | grep -q 1; then
    log "  Dropping database ${DB_NAME}..."
    # Terminate active connections before dropping
    docker exec harness-postgres psql -U harness -d harness_dev -c \
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}';" >/dev/null 2>&1 || true
    docker exec harness-postgres dropdb -U harness "${DB_NAME}" 2>/dev/null || true
  fi

  # Remove the git worktree
  if [[ -d "${WORKTREE_DIR}" ]]; then
    log "  Removing worktree ${WORKTREE_DIR}..."
    git -C "${REPO_ROOT}" worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || true
  fi

  # Prune worktree references
  git -C "${REPO_ROOT}" worktree prune 2>/dev/null || true

  if [[ ${exit_code} -ne 0 ]]; then
    log "Dispatch failed with exit code ${exit_code}."
  fi

  log "Cleanup complete."
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Post a structured progress comment on the issue
# ---------------------------------------------------------------------------
post_checkpoint() {
  local status="$1"   # in_progress | blocked | completed | escalated
  local done="$2"     # what was done
  local remaining="$3" # what remains
  local blockers="${4:-}" # blockers (optional)

  local body="## Dispatch Checkpoint

**Status**: \`${status}\`
**CI Round**: ${CI_ROUND}/${CI_BUDGET}

### Done
${done}

### Remaining
${remaining}"

  if [[ -n "${blockers}" ]]; then
    body+="

### Blockers
${blockers}"
  fi

  body+="

---
_Posted by \`scripts/dispatch.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  gh issue comment "${ISSUE_NUMBER}" --body "${body}"
}

# ---------------------------------------------------------------------------
# Post an escalation comment and label the issue
# ---------------------------------------------------------------------------
escalate() {
  local reason="$1"

  local body="## Escalation

**Status**: \`escalated\`
**CI Rounds Used**: ${CI_ROUND}/${CI_BUDGET}

### What was attempted
The dispatch agent worked on issue #${ISSUE_NUMBER} in an isolated environment.

### Where convergence failed
${reason}

### What human judgment is needed
Please review the issue description for clarity, check the linked PR (if any) for partial progress, and determine next steps. The agent environment has been cleaned up.

${PR_URL:+**Partial PR**: ${PR_URL}}

---
_Posted by \`scripts/dispatch.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  gh issue comment "${ISSUE_NUMBER}" --body "${body}"
  gh issue edit "${ISSUE_NUMBER}" --add-label "escalated"
  log "Issue #${ISSUE_NUMBER} escalated."
}

# ===========================================================================
# STEP 1: Validate preconditions
# ===========================================================================
log "=== Dispatch starting for issue #${ISSUE_NUMBER} ==="

# Verify gh CLI is authenticated
if ! gh auth status >/dev/null 2>&1; then
  log_error "GitHub CLI (gh) is not authenticated. Run 'gh auth login' first."
  exit 1
fi

# Verify the issue exists and fetch its metadata
log "Validating issue #${ISSUE_NUMBER}..."

ISSUE_JSON=$(gh issue view "${ISSUE_NUMBER}" --json title,body,labels,state)

ISSUE_STATE=$(echo "${ISSUE_JSON}" | jq -r '.state')
if [[ "${ISSUE_STATE}" != "OPEN" ]]; then
  log_error "Issue #${ISSUE_NUMBER} is not open (state: ${ISSUE_STATE})."
  exit 1
fi

ISSUE_TITLE=$(echo "${ISSUE_JSON}" | jq -r '.title')
ISSUE_BODY=$(echo "${ISSUE_JSON}" | jq -r '.body')
ISSUE_LABELS=$(echo "${ISSUE_JSON}" | jq -r '.labels[].name' 2>/dev/null || echo "")

# Check for ready-for-agent label
if ! echo "${ISSUE_LABELS}" | grep -q "^ready-for-agent$"; then
  log_error "Issue #${ISSUE_NUMBER} does not have the 'ready-for-agent' label."
  exit 1
fi

# Check for blocked label
if echo "${ISSUE_LABELS}" | grep -q "^blocked$"; then
  log_error "Issue #${ISSUE_NUMBER} is labeled 'blocked'. Resolve blockers first."
  exit 1
fi

# Check for ci-budget:N label override
BUDGET_LABEL=$(echo "${ISSUE_LABELS}" | grep -oP '^ci-budget:\K[0-9]+$' || true)
if [[ -n "${BUDGET_LABEL}" ]]; then
  CI_BUDGET="${BUDGET_LABEL}"
  log "CI budget overridden by label: ${CI_BUDGET}"
fi

log "Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}"
log "CI budget: ${CI_BUDGET} rounds"

# Check for concurrent dispatch — abort if worktree or container already exists
if [[ -d "${WORKTREE_DIR}" ]]; then
  log_error "Worktree already exists at ${WORKTREE_DIR}. Another dispatch may be in progress."
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
  log_error "Container ${CONTAINER_NAME} already exists. Another dispatch may be in progress."
  exit 1
fi

# ===========================================================================
# STEP 2: Create the isolated environment
# ===========================================================================

# Generate branch name from issue title
SLUG=$(echo "${ISSUE_TITLE}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-50)
BRANCH_NAME="issue-${ISSUE_NUMBER}/${SLUG}"

log "Creating worktree at ${WORKTREE_DIR} on branch ${BRANCH_NAME}..."
mkdir -p "${WORKTREE_BASE}"

# Fetch latest main
git -C "${REPO_ROOT}" fetch origin main --quiet

# Create the worktree with a new branch based on origin/main
git -C "${REPO_ROOT}" worktree add -b "${BRANCH_NAME}" "${WORKTREE_DIR}" origin/main

log "Worktree created."

# ===========================================================================
# STEP 3: Ensure Postgres is running and create the dispatch database
# ===========================================================================
log "Ensuring Postgres is running..."

# Start docker compose services if not already running
if ! docker ps --format '{{.Names}}' | grep -q "^harness-postgres$"; then
  log "Starting Docker Compose services..."
  docker compose -f "${DOCKER_COMPOSE_FILE}" up -d --wait
fi

# Wait for Postgres to be ready
log "Waiting for Postgres to be ready..."
for i in $(seq 1 30); do
  if docker exec harness-postgres pg_isready -U harness -d harness_dev >/dev/null 2>&1; then
    break
  fi
  if [[ ${i} -eq 30 ]]; then
    log_error "Postgres did not become ready in time."
    exit 1
  fi
  sleep 1
done

# Create the dispatch-specific database
log "Creating database ${DB_NAME}..."
docker exec harness-postgres createdb -U harness "${DB_NAME}" 2>/dev/null || {
  log "Database ${DB_NAME} already exists, dropping and recreating..."
  docker exec harness-postgres psql -U harness -d harness_dev -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}';" >/dev/null 2>&1 || true
  docker exec harness-postgres dropdb -U harness "${DB_NAME}"
  docker exec harness-postgres createdb -U harness "${DB_NAME}"
}

# Construct the dispatch-specific DATABASE_URL
DISPATCH_DB_URL="postgresql://harness:harness@localhost:5432/${DB_NAME}"

# ===========================================================================
# STEP 4: Seed the database
# ===========================================================================
log "Seeding database ${DB_NAME}..."

# Run migrations first (if any exist)
if ls "${WORKTREE_DIR}/src/server/db/migrations/"*.sql >/dev/null 2>&1; then
  log "Applying migrations..."
  DATABASE_URL="${DISPATCH_DB_URL}" npx --prefix "${WORKTREE_DIR}" drizzle-kit migrate 2>&1 || {
    log "Warning: Migration failed (may be expected if schema is stub-only)."
  }
fi

# Run the seed script
DATABASE_URL="${DISPATCH_DB_URL}" npx --prefix "${WORKTREE_DIR}" tsx "${WORKTREE_DIR}/scripts/seed.ts" 2>&1 || {
  log "Warning: Seed script failed (may be expected if schema is stub-only)."
}

log "Database seeded."

# ===========================================================================
# STEP 5: Start the dispatch Docker container
# ===========================================================================
log "Starting container ${CONTAINER_NAME}..."

# Build the dev image if needed
docker build -t harness-dev -f "${DOCKERFILE_DEV}" "${WORKTREE_DIR}" --quiet 2>&1 || {
  log "Warning: Docker image build failed. Continuing without container."
}

# Run the container with the worktree mounted and database URL set
docker run -d \
  --name "${CONTAINER_NAME}" \
  --network host \
  -e DATABASE_URL="${DISPATCH_DB_URL}" \
  -e NODE_ENV=development \
  -e SKIP_ENV_VALIDATION=1 \
  -v "${WORKTREE_DIR}:/app" \
  -w /app \
  harness-dev \
  tail -f /dev/null >/dev/null 2>&1 || {
  log "Warning: Container start failed. Continuing without container isolation."
}

# Install dependencies in the worktree
log "Installing dependencies in worktree..."
(cd "${WORKTREE_DIR}" && npm ci --quiet 2>&1) || {
  log "Warning: npm ci failed in worktree."
}

log "Container ${CONTAINER_NAME} started."

# ===========================================================================
# STEP 6: Post initial checkpoint
# ===========================================================================
post_checkpoint "in_progress" \
  "Environment created: worktree at \`${WORKTREE_DIR}\`, database \`${DB_NAME}\`, container \`${CONTAINER_NAME}\`." \
  "Agent invocation pending."

# ===========================================================================
# STEP 7: Invoke Claude Code
# ===========================================================================
log "Invoking Claude Code..."

# Build the agent prompt from the issue
AGENT_PROMPT="You are an implementation agent executing a GitHub issue in an isolated environment.

## Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}

## Instructions

1. Read the CLAUDE.md tree (root and relevant subdirectories) to understand conventions.
2. Read existing code before modifying anything.
3. Implement the smallest viable diff that resolves this issue.
4. Write tests per the testing conventions in tests/CLAUDE.md.
5. Run lint, typecheck, and tests before committing.
6. Create a single PR linked to issue #${ISSUE_NUMBER}.
7. If this is the first implementation of a pattern in a directory, update that directory's CLAUDE.md.
8. If the issue is ambiguous or missing information, post a comment explaining what is missing and stop.

## Environment

- Database URL: ${DISPATCH_DB_URL}
- Working directory: ${WORKTREE_DIR}
- Branch: ${BRANCH_NAME}
- Container: ${CONTAINER_NAME}

## Commit Convention

Use conventional commits: type(scope): description
Branch is already created. Push to origin when ready.

## PR Convention

Link to issue #${ISSUE_NUMBER} with 'Closes #${ISSUE_NUMBER}' in the PR body.
Include a summary of changes, test plan, and any convention doc updates."

# CI budget loop: allow up to CI_BUDGET rounds of push → CI → fix
while [[ ${CI_ROUND} -lt ${CI_BUDGET} ]]; do
  CI_ROUND=$((CI_ROUND + 1))
  log "CI round ${CI_ROUND}/${CI_BUDGET}..."

  if [[ "${DISPATCH_DRY_RUN:-}" == "1" ]]; then
    log "DRY RUN: Skipping Claude Code invocation."
    # In dry run mode, simulate a successful run
    (cd "${WORKTREE_DIR}" && \
      git commit --allow-empty -m "chore: dry run dispatch for issue #${ISSUE_NUMBER}" && \
      git push -u origin "${BRANCH_NAME}" 2>/dev/null || true)
    break
  fi

  # Invoke Claude Code in the worktree
  # The agent works in the worktree directory with full access to the codebase
  if claude --dangerously-skip-permissions \
    --print \
    --output-format text \
    --max-turns 50 \
    -p "${AGENT_PROMPT}" \
    2>&1; then
    log "Claude Code completed successfully."
  else
    log "Claude Code exited with non-zero status."
  fi

  # Check if a PR was already created
  EXISTING_PR=$(gh pr list --head "${BRANCH_NAME}" --json number,url --jq '.[0].url' 2>/dev/null || echo "")
  if [[ -n "${EXISTING_PR}" ]]; then
    PR_URL="${EXISTING_PR}"
    log "PR found: ${PR_URL}"
    break
  fi

  # Check if there are commits to push
  if git -C "${WORKTREE_DIR}" log --oneline origin/main..HEAD 2>/dev/null | head -1 | grep -q .; then
    # Push the branch
    log "Pushing branch ${BRANCH_NAME}..."
    git -C "${WORKTREE_DIR}" push -u origin "${BRANCH_NAME}" 2>&1 || true

    # Wait for CI to run and check results
    log "Waiting for CI checks..."
    sleep 10  # Give CI a moment to start

    # Check if CI passes (simplified — in production this would poll CI status)
    CI_STATUS=$(gh pr checks --json 'state' --jq '.[].state' 2>/dev/null || echo "PENDING")

    if echo "${CI_STATUS}" | grep -q "FAILURE"; then
      log "CI failed on round ${CI_ROUND}. Agent will attempt to fix."
      AGENT_PROMPT="CI checks failed on your previous push. Please read the CI output, fix the issues, and push again. This is CI round ${CI_ROUND}/${CI_BUDGET}."
      continue
    fi

    # Create the PR if one doesn't exist yet
    if [[ -z "${PR_URL}" ]]; then
      log "Creating PR..."
      PR_URL=$(gh pr create \
        --title "Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}" \
        --body "$(cat <<EOF
## Summary

Resolves #${ISSUE_NUMBER}.

Implementation produced by the dispatch agent in an isolated environment.

## Linked Issue

Closes #${ISSUE_NUMBER}

## CI Rounds

${CI_ROUND}/${CI_BUDGET} CI rounds used.

---
_Created by \`scripts/dispatch.sh\`_
EOF
)" \
        --head "${BRANCH_NAME}" \
        --base main 2>&1) || {
        log "Warning: PR creation failed."
        PR_URL=""
      }

      if [[ -n "${PR_URL}" ]]; then
        log "PR created: ${PR_URL}"
      fi
    fi
    break
  else
    log "No commits produced in round ${CI_ROUND}."
    if [[ ${CI_ROUND} -ge ${CI_BUDGET} ]]; then
      break
    fi
    AGENT_PROMPT="You did not produce any commits in the previous round. Please implement the issue and commit your changes. This is CI round ${CI_ROUND}/${CI_BUDGET}."
  fi
done

# ===========================================================================
# STEP 8: Handle CI budget exhaustion
# ===========================================================================
if [[ ${CI_ROUND} -ge ${CI_BUDGET} && -z "${PR_URL}" ]]; then
  log "CI budget exhausted (${CI_BUDGET} rounds) without producing a PR."
  escalate "CI budget exhausted after ${CI_BUDGET} rounds. The agent could not produce a passing PR within the allotted cycles."
  exit 1
fi

# ===========================================================================
# STEP 9: Link PR to issue and trigger review
# ===========================================================================
if [[ -n "${PR_URL}" ]]; then
  log "PR linked to issue #${ISSUE_NUMBER}: ${PR_URL}"

  # Extract PR number from URL (e.g., https://github.com/owner/repo/pull/42 → 42)
  PR_NUMBER_FOR_REVIEW=$(echo "${PR_URL}" | grep -oP '/pull/\K[0-9]+' || \
    gh pr list --head "${BRANCH_NAME}" --json number --jq '.[0].number' 2>/dev/null || echo "")

  # Post completion checkpoint
  post_checkpoint "completed" \
    "Implementation complete. PR created: ${PR_URL}" \
    "Awaiting review."

  if [[ -z "${PR_NUMBER_FOR_REVIEW}" ]]; then
    log "Warning: Could not extract PR number from URL. Skipping review."
  else
    # Trigger the review pipeline
    log "Triggering review pipeline for PR #${PR_NUMBER_FOR_REVIEW}..."
    "${REPO_ROOT}/scripts/review.sh" "${PR_NUMBER_FOR_REVIEW}" --budget "${CI_BUDGET}" || {
      log "Review pipeline exited with non-zero status."
      # Review escalation is handled within review.sh — don't fail dispatch
    }
  fi
else
  log "No PR was created."
  post_checkpoint "blocked" \
    "Dispatch completed but no PR was produced." \
    "Manual investigation needed." \
    "Agent did not produce commits or create a PR."
fi

# ===========================================================================
# STEP 10: Done
# ===========================================================================
log "=== Dispatch complete for issue #${ISSUE_NUMBER} ==="
if [[ -n "${PR_URL}" ]]; then
  log "PR: ${PR_URL}"
fi
