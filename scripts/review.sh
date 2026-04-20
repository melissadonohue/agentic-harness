#!/usr/bin/env bash
# =============================================================================
# Agentic Harness — Review Orchestrator
# =============================================================================
# Usage: scripts/review.sh <pr-number> [--budget N]
#
# Orchestrates /review: reads the PR diff, linked issue, and relevant CLAUDE.md
# files, then invokes a fresh Claude Code session as a reviewer. Handles the
# multi-pass review protocol (reviewer posts feedback → author fixes → re-review)
# and escalation when the retry limit is reached.
#
# The reviewer is ALWAYS a separate Claude Code session — fresh invocation with
# no memory of the authoring process. It evaluates output, not reasoning.
#
# Flags:
#   --budget N    Override the default review budget (default: 5)
#
# Environment:
#   GITHUB_TOKEN         Required for gh CLI operations
#   REVIEW_BUDGET        Override default review budget (default: 5)
#   REVIEW_DRY_RUN       If set to "1", skip Claude Code invocations (for testing)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_REVIEW_BUDGET=5
SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: ${SCRIPT_NAME} <pr-number> [--budget N]"
  echo ""
  echo "  pr-number   GitHub PR number to review"
  echo "  --budget N  Override the review retry limit (default: ${DEFAULT_REVIEW_BUDGET})"
  exit 1
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  echo "[review] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_error() {
  echo "[review] $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PR_NUMBER=""
REVIEW_BUDGET="${REVIEW_BUDGET:-${DEFAULT_REVIEW_BUDGET}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget)
      if [[ -z "${2:-}" ]]; then
        log_error "--budget requires a numeric argument"
        usage
      fi
      REVIEW_BUDGET="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [[ -z "${PR_NUMBER}" ]]; then
        PR_NUMBER="$1"
      else
        log_error "Unexpected argument: $1"
        usage
      fi
      shift
      ;;
  esac
done

if [[ -z "${PR_NUMBER}" ]]; then
  log_error "Missing required argument: pr-number"
  usage
fi

# Validate PR number is numeric
if ! [[ "${PR_NUMBER}" =~ ^[0-9]+$ ]]; then
  log_error "PR number must be numeric, got: ${PR_NUMBER}"
  exit 1
fi

# Validate budget is numeric
if ! [[ "${REVIEW_BUDGET}" =~ ^[0-9]+$ ]]; then
  log_error "Review budget must be numeric, got: ${REVIEW_BUDGET}"
  exit 1
fi

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
REVIEW_ROUND=0
REVIEW_STATUS="pending"  # pending | changes_requested | approved | escalated

# ===========================================================================
# STEP 1: Read PR metadata
# ===========================================================================
log "=== Review starting for PR #${PR_NUMBER} ==="

# Verify gh CLI is authenticated
if ! gh auth status >/dev/null 2>&1; then
  log_error "GitHub CLI (gh) is not authenticated. Run 'gh auth login' first."
  exit 1
fi

# Fetch PR metadata
log "Reading PR #${PR_NUMBER} metadata..."
PR_JSON=$(gh pr view "${PR_NUMBER}" --json number,title,body,headRefName,baseRefName,state,files,url,closingIssuesReferences)

PR_STATE=$(echo "${PR_JSON}" | jq -r '.state')
if [[ "${PR_STATE}" != "OPEN" ]]; then
  log_error "PR #${PR_NUMBER} is not open (state: ${PR_STATE})."
  exit 1
fi

PR_TITLE=$(echo "${PR_JSON}" | jq -r '.title')
PR_BODY=$(echo "${PR_JSON}" | jq -r '.body')
PR_BRANCH=$(echo "${PR_JSON}" | jq -r '.headRefName')
PR_BASE=$(echo "${PR_JSON}" | jq -r '.baseRefName')
PR_URL=$(echo "${PR_JSON}" | jq -r '.url')

# Get the list of changed files
CHANGED_FILES=$(echo "${PR_JSON}" | jq -r '.files[].path')
CHANGED_FILE_COUNT=$(echo "${PR_JSON}" | jq '.files | length')

log "PR #${PR_NUMBER}: ${PR_TITLE}"
log "Branch: ${PR_BRANCH} → ${PR_BASE}"
log "Changed files: ${CHANGED_FILE_COUNT}"

# ---------------------------------------------------------------------------
# Extract linked issue number
# ---------------------------------------------------------------------------
# Try closingIssuesReferences first
LINKED_ISSUE=$(echo "${PR_JSON}" | jq -r '.closingIssuesReferences[0].number // empty' 2>/dev/null || echo "")

# Fall back to parsing the PR body for "Closes #N" or "Resolves #N"
if [[ -z "${LINKED_ISSUE}" ]]; then
  LINKED_ISSUE=$(echo "${PR_BODY}" | grep -oP '(?:Closes|Resolves|Fixes)\s+#\K[0-9]+' | head -1 || echo "")
fi

ISSUE_BODY=""
ISSUE_TITLE=""
if [[ -n "${LINKED_ISSUE}" ]]; then
  log "Linked issue: #${LINKED_ISSUE}"
  ISSUE_JSON=$(gh issue view "${LINKED_ISSUE}" --json title,body 2>/dev/null || echo "")
  if [[ -n "${ISSUE_JSON}" ]]; then
    ISSUE_TITLE=$(echo "${ISSUE_JSON}" | jq -r '.title')
    ISSUE_BODY=$(echo "${ISSUE_JSON}" | jq -r '.body')
  fi
else
  log "Warning: No linked issue found. Review will proceed without spec context."
fi

# ===========================================================================
# STEP 2: Gather review context — changed files and transitive dependencies
# ===========================================================================
log "Gathering review context..."

# Get the full diff
PR_DIFF=$(gh pr diff "${PR_NUMBER}" --color=never 2>/dev/null || echo "")

if [[ -z "${PR_DIFF}" ]]; then
  log_error "Could not read PR diff. The PR may have no changes."
  exit 1
fi

# ---------------------------------------------------------------------------
# Identify relevant CLAUDE.md files based on changed file paths
# ---------------------------------------------------------------------------
gather_claude_md_files() {
  local claude_md_files=""

  # Always include root CLAUDE.md
  claude_md_files="CLAUDE.md"

  # For each changed file, walk up directories looking for CLAUDE.md
  while IFS= read -r file; do
    local dir
    dir=$(dirname "${file}")
    while [[ "${dir}" != "." && "${dir}" != "/" ]]; do
      local candidate="${dir}/CLAUDE.md"
      if [[ -f "${REPO_ROOT}/${candidate}" ]]; then
        if ! echo "${claude_md_files}" | grep -qF "${candidate}"; then
          claude_md_files="${claude_md_files}"$'\n'"${candidate}"
        fi
      fi
      dir=$(dirname "${dir}")
    done
  done <<< "${CHANGED_FILES}"

  echo "${claude_md_files}"
}

CLAUDE_MD_FILES=$(gather_claude_md_files)
CLAUDE_MD_COUNT=$(echo "${CLAUDE_MD_FILES}" | wc -l | tr -d ' ')
log "Relevant CLAUDE.md files: ${CLAUDE_MD_COUNT}"

# Read the contents of all relevant CLAUDE.md files
CLAUDE_MD_CONTEXT=""
while IFS= read -r md_file; do
  if [[ -f "${REPO_ROOT}/${md_file}" ]]; then
    CLAUDE_MD_CONTEXT+="
--- ${md_file} ---
$(cat "${REPO_ROOT}/${md_file}")
"
  fi
done <<< "${CLAUDE_MD_FILES}"

# ---------------------------------------------------------------------------
# Gather transitive dependency context (one level)
# ---------------------------------------------------------------------------
gather_transitive_deps() {
  local dep_files=""

  while IFS= read -r file; do
    # Only process TypeScript/JavaScript files
    if [[ "${file}" =~ \.(ts|tsx|js|jsx)$ ]] && [[ -f "${REPO_ROOT}/${file}" ]]; then
      # Extract imports from the file
      local imports
      imports=$(grep -oP "from ['\"](@/[^'\"]+|\.\.?/[^'\"]+)['\"]" "${REPO_ROOT}/${file}" 2>/dev/null || echo "")

      while IFS= read -r import_line; do
        if [[ -z "${import_line}" ]]; then continue; fi

        # Extract the path
        local import_path
        import_path=$(echo "${import_line}" | grep -oP "(?:from ['\"])(.+)(?:['\"])" | sed "s/from ['\"]//;s/['\"]//g")

        if [[ -z "${import_path}" ]]; then continue; fi

        # Resolve @ alias to src/
        if [[ "${import_path}" == @/* ]]; then
          import_path="src/${import_path#@/}"
        fi

        # Resolve relative paths
        if [[ "${import_path}" == ./* || "${import_path}" == ../* ]]; then
          local file_dir
          file_dir=$(dirname "${file}")
          import_path=$(cd "${REPO_ROOT}/${file_dir}" && realpath --relative-to="${REPO_ROOT}" "${import_path}" 2>/dev/null || echo "")
        fi

        if [[ -z "${import_path}" ]]; then continue; fi

        # Try common extensions if no extension specified
        local resolved=""
        for ext in "" ".ts" ".tsx" ".js" ".jsx" "/index.ts" "/index.tsx" "/index.js"; do
          local candidate="${import_path}${ext}"
          if [[ -f "${REPO_ROOT}/${candidate}" ]]; then
            resolved="${candidate}"
            break
          fi
        done

        # Add if resolved and not already in changed files
        if [[ -n "${resolved}" ]] && ! echo "${CHANGED_FILES}" | grep -qF "${resolved}"; then
          if ! echo "${dep_files}" | grep -qF "${resolved}"; then
            dep_files="${dep_files}"$'\n'"${resolved}"
          fi
        fi
      done <<< "${imports}"
    fi
  done <<< "${CHANGED_FILES}"

  echo "${dep_files}" | sed '/^$/d'
}

TRANSITIVE_DEPS=$(gather_transitive_deps)
if [[ -n "${TRANSITIVE_DEPS}" ]]; then
  DEP_COUNT=$(echo "${TRANSITIVE_DEPS}" | wc -l | tr -d ' ')
  log "Transitive dependencies (one level): ${DEP_COUNT} files"
else
  log "No transitive dependencies found."
fi

# ===========================================================================
# STEP 3: Multi-pass review loop
# ===========================================================================

# ---------------------------------------------------------------------------
# Build the reviewer prompt
# ---------------------------------------------------------------------------
build_reviewer_prompt() {
  local round="$1"
  local previous_reviews="${2:-}"

  cat <<REVIEWER_PROMPT
You are a review agent evaluating a pull request. You are a FRESH session with NO memory of the authoring process. Evaluate the OUTPUT, not the reasoning.

## PR #${PR_NUMBER}: ${PR_TITLE}

**Branch**: ${PR_BRANCH} → ${PR_BASE}
**Changed files**: ${CHANGED_FILE_COUNT}
**Review round**: ${round}/${REVIEW_BUDGET}

## PR Description

${PR_BODY}

## Linked Issue${LINKED_ISSUE:+ #${LINKED_ISSUE}: ${ISSUE_TITLE}}

${ISSUE_BODY:-No linked issue found. Evaluate the PR on its own merits.}

## Codebase Conventions

${CLAUDE_MD_CONTEXT}

## PR Diff

\`\`\`diff
${PR_DIFF}
\`\`\`

${previous_reviews:+## Previous Review Rounds

${previous_reviews}}

## Review Criteria

Evaluate the PR against these criteria. For each criterion, provide a rating (pass/fail/not-applicable) and a brief explanation.

1. **Correctness**: Does the PR resolve the linked issue? Does the implementation match the spec?
2. **Conventions**: Does the PR follow the CLAUDE.md rules? File naming, import ordering, vendor seam boundaries, error handling patterns?
3. **Tests**: Are tests sufficient and meaningful? Do they cover the key behaviors, not just happy paths?
4. **Types**: Are TypeScript types precise? No \`any\` types? No overly broad types?
5. **Accessibility**: For UI changes — do they meet AA standard? Semantic HTML, ARIA attributes, keyboard navigation?

## Output Format

You MUST output your review in EXACTLY this format (it will be parsed programmatically):

\`\`\`
REVIEW_STATUS: APPROVED | CHANGES_REQUESTED
\`\`\`

### Summary

One-paragraph summary of the review.

### Issues Found

For each issue, use this format:
- **[CRITERION] severity**: Description of the issue. File: \`path/to/file\`, line N.

Severity levels: \`blocking\` (must fix before merge), \`suggestion\` (improve but not blocking), \`nit\` (trivial, ignore if you want).

### Issues Resolved Since Last Review

(Only for round 2+. List issues from the previous review that have been addressed.)

### Remaining Concerns

(Only for round 2+. List issues from the previous review that are still unresolved.)

---

Be rigorous but fair. The goal is to catch real problems, not to nitpick style that linters already enforce. If the PR is clean, approve it. Do not request changes for trivial preferences.
REVIEWER_PROMPT
}

# ---------------------------------------------------------------------------
# Build the author revision prompt
# ---------------------------------------------------------------------------
build_author_prompt() {
  local review_comment="$1"
  local round="$2"

  cat <<AUTHOR_PROMPT
You are an implementation agent addressing review feedback on a pull request.

## PR #${PR_NUMBER}: ${PR_TITLE}

**Branch**: ${PR_BRANCH}
**Review round**: ${round}/${REVIEW_BUDGET}

## Review Feedback

${review_comment}

## Instructions

1. Read the review feedback carefully.
2. Address ALL blocking issues. Suggestions and nits are optional but encouraged.
3. Read each file mentioned before modifying it.
4. Run lint, typecheck, and tests before committing.
5. Commit with a message referencing the review round: \`fix(review): address round ${round} feedback\`
6. Push to the existing branch: ${PR_BRANCH}
7. Do NOT create a new PR. Push to the same branch to update the existing PR.

## Environment

- Working directory: the repo root
- Branch: ${PR_BRANCH} (already checked out)

Focus on the blocking issues. Be precise and minimal in your changes.
AUTHOR_PROMPT
}

# ---------------------------------------------------------------------------
# Post a structured review comment on the PR
# ---------------------------------------------------------------------------
post_review_comment() {
  local round="$1"
  local review_output="$2"
  local status="$3"

  local body="## Agent Review — Round ${round}/${REVIEW_BUDGET}

**Status**: \`${status}\`

${review_output}

---
_Posted by \`scripts/review.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  gh pr comment "${PR_NUMBER}" --body "${body}"
}

# ---------------------------------------------------------------------------
# Parse the review status from reviewer output
# ---------------------------------------------------------------------------
parse_review_status() {
  local output="$1"

  if echo "${output}" | grep -qP 'REVIEW_STATUS:\s*APPROVED'; then
    echo "approved"
  elif echo "${output}" | grep -qP 'REVIEW_STATUS:\s*CHANGES_REQUESTED'; then
    echo "changes_requested"
  else
    # Default to changes_requested if status is ambiguous
    log "Warning: Could not parse REVIEW_STATUS from reviewer output. Defaulting to changes_requested."
    echo "changes_requested"
  fi
}

# ---------------------------------------------------------------------------
# Post escalation comment and label the PR
# ---------------------------------------------------------------------------
escalate_review() {
  local all_reviews="$1"

  local body="## Review Escalation

**Status**: \`escalated\`
**Review Rounds Used**: ${REVIEW_ROUND}/${REVIEW_BUDGET}

### What was attempted

The review agent and implementation agent iterated for ${REVIEW_ROUND} rounds on PR #${PR_NUMBER} without reaching approval.

### Unresolved Concerns

The following issues could not be resolved within the review budget:

${all_reviews}

### What human judgment is needed

Please review the PR diff, the review comments above, and the linked issue${LINKED_ISSUE:+ (#${LINKED_ISSUE})}. Determine whether the remaining concerns are blocking or acceptable, and either approve, request further changes, or close the PR.

---
_Posted by \`scripts/review.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  gh pr comment "${PR_NUMBER}" --body "${body}"
  gh pr edit "${PR_NUMBER}" --add-label "escalated"
  log "PR #${PR_NUMBER} escalated after ${REVIEW_ROUND} review rounds."
}

# ===========================================================================
# Main review loop
# ===========================================================================
ALL_REVIEWS=""

while [[ ${REVIEW_ROUND} -lt ${REVIEW_BUDGET} ]]; do
  REVIEW_ROUND=$((REVIEW_ROUND + 1))
  log "=== Review round ${REVIEW_ROUND}/${REVIEW_BUDGET} ==="

  # Re-read the diff on rounds 2+ (author may have pushed fixes)
  if [[ ${REVIEW_ROUND} -gt 1 ]]; then
    log "Re-reading PR diff after author revisions..."
    PR_DIFF=$(gh pr diff "${PR_NUMBER}" --color=never 2>/dev/null || echo "")
    if [[ -z "${PR_DIFF}" ]]; then
      log_error "Could not read PR diff on round ${REVIEW_ROUND}."
      break
    fi

    # Re-read changed files list
    PR_JSON_UPDATED=$(gh pr view "${PR_NUMBER}" --json files)
    CHANGED_FILES=$(echo "${PR_JSON_UPDATED}" | jq -r '.files[].path')
    CHANGED_FILE_COUNT=$(echo "${PR_JSON_UPDATED}" | jq '.files | length')
  fi

  # -------------------------------------------------------------------------
  # Invoke the reviewer (fresh Claude Code session)
  # -------------------------------------------------------------------------
  REVIEWER_PROMPT=$(build_reviewer_prompt "${REVIEW_ROUND}" "${ALL_REVIEWS}")
  REVIEWER_OUTPUT=""

  if [[ "${REVIEW_DRY_RUN:-}" == "1" ]]; then
    log "DRY RUN: Skipping reviewer invocation."
    REVIEWER_OUTPUT="REVIEW_STATUS: APPROVED

### Summary

Dry run — auto-approving.

### Issues Found

None (dry run)."
  else
    log "Invoking reviewer agent (fresh session)..."

    # Capture reviewer output
    REVIEWER_OUTPUT=$(claude --dangerously-skip-permissions \
      --print \
      --output-format text \
      --max-turns 10 \
      -p "${REVIEWER_PROMPT}" \
      2>&1) || {
      log "Warning: Reviewer agent exited with non-zero status."
    }
  fi

  # Parse the review status
  REVIEW_STATUS=$(parse_review_status "${REVIEWER_OUTPUT}")
  log "Review status: ${REVIEW_STATUS}"

  # Post the review comment on the PR
  post_review_comment "${REVIEW_ROUND}" "${REVIEWER_OUTPUT}" "${REVIEW_STATUS}"

  # Accumulate reviews for escalation context
  ALL_REVIEWS+="
### Round ${REVIEW_ROUND}
${REVIEWER_OUTPUT}
"

  # -------------------------------------------------------------------------
  # Handle the review result
  # -------------------------------------------------------------------------
  if [[ "${REVIEW_STATUS}" == "approved" ]]; then
    log "PR #${PR_NUMBER} approved on round ${REVIEW_ROUND}."
    break
  fi

  # If this is the last round, don't invoke the author — we'll escalate
  if [[ ${REVIEW_ROUND} -ge ${REVIEW_BUDGET} ]]; then
    log "Review budget exhausted."
    break
  fi

  # -------------------------------------------------------------------------
  # Invoke the author to address feedback
  # -------------------------------------------------------------------------
  log "Invoking author agent to address review feedback..."

  AUTHOR_PROMPT=$(build_author_prompt "${REVIEWER_OUTPUT}" "${REVIEW_ROUND}")

  if [[ "${REVIEW_DRY_RUN:-}" == "1" ]]; then
    log "DRY RUN: Skipping author invocation."
  else
    # Check out the PR branch
    WORKTREE_DIR="${REPO_ROOT}/.worktrees/review-${PR_NUMBER}"
    mkdir -p "$(dirname "${WORKTREE_DIR}")"

    # Create a worktree for the author revision if it doesn't exist
    if [[ ! -d "${WORKTREE_DIR}" ]]; then
      git -C "${REPO_ROOT}" fetch origin "${PR_BRANCH}" --quiet
      git -C "${REPO_ROOT}" worktree add "${WORKTREE_DIR}" "origin/${PR_BRANCH}" 2>/dev/null || {
        # If worktree already exists at a different path, reuse it
        log "Warning: Could not create worktree. Attempting to work in repo root."
        WORKTREE_DIR="${REPO_ROOT}"
      }
    else
      # Update existing worktree
      git -C "${WORKTREE_DIR}" fetch origin "${PR_BRANCH}" --quiet
      git -C "${WORKTREE_DIR}" checkout "${PR_BRANCH}" 2>/dev/null || true
      git -C "${WORKTREE_DIR}" pull origin "${PR_BRANCH}" --quiet 2>/dev/null || true
    fi

    # Install dependencies if in a separate worktree
    if [[ "${WORKTREE_DIR}" != "${REPO_ROOT}" ]]; then
      (cd "${WORKTREE_DIR}" && npm ci --quiet 2>&1) || {
        log "Warning: npm ci failed in review worktree."
      }
    fi

    # Invoke Claude Code as the author to fix issues
    (cd "${WORKTREE_DIR}" && claude --dangerously-skip-permissions \
      --print \
      --output-format text \
      --max-turns 30 \
      -p "${AUTHOR_PROMPT}" \
      2>&1) || {
      log "Warning: Author agent exited with non-zero status."
    }

    # Push author's changes
    if git -C "${WORKTREE_DIR}" log --oneline "origin/${PR_BRANCH}..HEAD" 2>/dev/null | head -1 | grep -q .; then
      log "Pushing author's revisions..."
      git -C "${WORKTREE_DIR}" push origin "${PR_BRANCH}" 2>&1 || {
        log "Warning: Push failed."
      }
    else
      log "Author produced no new commits."
    fi

    # Clean up the review worktree
    if [[ "${WORKTREE_DIR}" != "${REPO_ROOT}" && -d "${WORKTREE_DIR}" ]]; then
      git -C "${REPO_ROOT}" worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || true
      git -C "${REPO_ROOT}" worktree prune 2>/dev/null || true
    fi
  fi

  log "Round ${REVIEW_ROUND} complete. Proceeding to re-review."
done

# ===========================================================================
# STEP 4: Handle final outcome
# ===========================================================================
if [[ "${REVIEW_STATUS}" == "approved" ]]; then
  log "=== Review complete: APPROVED ==="
  log "PR #${PR_NUMBER} passed agent review after ${REVIEW_ROUND} round(s)."

  # Post a final summary comment
  gh pr comment "${PR_NUMBER}" --body "$(cat <<EOF
## Review Complete

**Result**: Approved
**Rounds**: ${REVIEW_ROUND}/${REVIEW_BUDGET}

This PR has passed agent-to-agent review and is ready for human review.

${LINKED_ISSUE:+**Linked Issue**: #${LINKED_ISSUE}}

---
_Posted by \`scripts/review.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_
EOF
)"

  exit 0

elif [[ ${REVIEW_ROUND} -ge ${REVIEW_BUDGET} && "${REVIEW_STATUS}" != "approved" ]]; then
  log "=== Review complete: ESCALATED ==="
  escalate_review "${ALL_REVIEWS}"
  exit 1

else
  log "=== Review ended unexpectedly ==="
  log "Status: ${REVIEW_STATUS}, Round: ${REVIEW_ROUND}"
  exit 1
fi
