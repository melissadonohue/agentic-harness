#!/usr/bin/env bash
# =============================================================================
# Agentic Harness — Triage Orchestrator
# =============================================================================
# Usage: scripts/triage.sh <issue-number> [--approve]
#
# Orchestrates /triage: two-tier intake and readiness system.
#
# Tier 1 — Intake: For product-level briefs (labeled `product-brief` or
#   auto-detected). The intake agent reads the codebase and CLAUDE.md
#   conventions, proposes a decomposition into implementation issues, and
#   posts it as a comment for human approval.
#
# Tier 2 — Readiness: For implementation-level issues. Evaluates whether
#   the issue has enough detail for dispatch. Either labels it
#   `ready-for-agent`, flags missing inputs, or proposes further breakdown.
#
# --approve: Creates child issues from an approved decomposition comment on
#   a product brief. Detected via "approved" comment or `decomposition-approved`
#   label.
#
# Environment:
#   GITHUB_TOKEN         Required for gh CLI operations
#   TRIAGE_DRY_RUN       If set to "1", skip Claude Code invocations (for testing)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Global state (set during execution)
# ---------------------------------------------------------------------------
ISSUE_NUMBER=""
APPROVE_MODE=false
ISSUE_JSON=""
ISSUE_TITLE=""
ISSUE_BODY=""
ISSUE_LABELS=""
DECOMPOSITION_COMMENT=""
TIER=""

# Used by create_single_issue to accumulate output for the parent comment
created_issues=""

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: ${SCRIPT_NAME} <issue-number> [--approve]"
  echo ""
  echo "  issue-number   GitHub issue number to triage"
  echo "  --approve      Create child issues from an approved decomposition"
  exit 1
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  echo "[triage] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_error() {
  echo "[triage] $(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2
}

# ---------------------------------------------------------------------------
# Auto-detection: product-level vs implementation-level
# ---------------------------------------------------------------------------
detect_issue_tier() {
  local body="$1"

  # Product-level signals: user outcomes, no file paths, no code references
  local product_signals=0
  local impl_signals=0

  # Product-level indicators
  if echo "${body}" | grep -qiP '(users?\s+(need|should|can|want|must)|as a user|user stor)'; then
    product_signals=$((product_signals + 2))
  fi
  if echo "${body}" | grep -qiP '(ability to|able to|so that|in order to)'; then
    product_signals=$((product_signals + 1))
  fi
  if echo "${body}" | grep -qiP '(sign[- ]?up|sign[- ]?in|onboard|dashboard|landing page|notification|invite|permission)' && \
     ! echo "${body}" | grep -qP '(\.tsx?|\.jsx?|src/|import |export |function )'; then
    product_signals=$((product_signals + 1))
  fi

  # Implementation-level indicators
  if echo "${body}" | grep -qP '(src/|\.tsx?|\.jsx?|\.sh)'; then
    impl_signals=$((impl_signals + 2))
  fi
  if echo "${body}" | grep -qP '(import |export |function |const |interface |type )'; then
    impl_signals=$((impl_signals + 2))
  fi
  if echo "${body}" | grep -qP '(schema/|repos/|api/|route\.ts|migration)'; then
    impl_signals=$((impl_signals + 1))
  fi
  if echo "${body}" | grep -qiP '(add .* to|create .* file|update .* config|implement .* function)' && \
     echo "${body}" | grep -qP '(\.tsx?|src/)'; then
    impl_signals=$((impl_signals + 1))
  fi

  if [[ ${product_signals} -ge 2 && ${impl_signals} -lt 2 ]]; then
    log "Tier 1 (Intake): Auto-detected product-level language (product=${product_signals}, impl=${impl_signals})."
    echo "intake"
  elif [[ ${impl_signals} -ge 2 ]]; then
    log "Tier 2 (Readiness): Auto-detected implementation-level language (product=${product_signals}, impl=${impl_signals})."
    echo "readiness"
  else
    echo ""  # Ambiguous — will fall through to default (readiness)
  fi
}

# ---------------------------------------------------------------------------
# Gather full codebase context for intake (Tier 1)
# ---------------------------------------------------------------------------
gather_codebase_context() {
  local context=""

  # Root CLAUDE.md
  if [[ -f "${REPO_ROOT}/CLAUDE.md" ]]; then
    context+="
--- CLAUDE.md (root) ---
$(cat "${REPO_ROOT}/CLAUDE.md")
"
  fi

  # All subdirectory CLAUDE.md files
  while IFS= read -r md_file; do
    local relative_path="${md_file#"${REPO_ROOT}/"}"
    context+="
--- ${relative_path} ---
$(cat "${md_file}")
"
  done < <(find "${REPO_ROOT}/src" "${REPO_ROOT}/tests" "${REPO_ROOT}/docker" "${REPO_ROOT}/scripts" "${REPO_ROOT}/docs" "${REPO_ROOT}/eslint-rules" \
    -name "CLAUDE.md" -type f 2>/dev/null | sort)

  # Current schema files (if any exist)
  local schema_dir="${REPO_ROOT}/src/server/db/schema"
  if [[ -d "${schema_dir}" ]]; then
    local schema_files
    schema_files=$(find "${schema_dir}" -name "*.ts" -type f 2>/dev/null | sort)
    if [[ -n "${schema_files}" ]]; then
      context+="
--- Database Schema Files ---"
      while IFS= read -r schema_file; do
        local fname
        fname=$(basename "${schema_file}")
        context+="
# ${fname}
$(cat "${schema_file}")
"
      done <<< "${schema_files}"
    fi
  fi

  # Current route structure
  local app_dir="${REPO_ROOT}/src/app"
  if [[ -d "${app_dir}" ]]; then
    context+="
--- Route Structure ---
$(find "${app_dir}" \( -name "page.tsx" -o -name "route.ts" \) 2>/dev/null | sed "s|${REPO_ROOT}/||" | sort)
"
  fi

  # Existing seam interfaces
  local server_dir="${REPO_ROOT}/src/server"
  if [[ -d "${server_dir}" ]]; then
    local types_files
    types_files=$(find "${server_dir}" -name "types.ts" -type f 2>/dev/null | sort)
    if [[ -n "${types_files}" ]]; then
      context+="
--- Seam Interface Types ---"
      while IFS= read -r types_file; do
        local rel_path="${types_file#"${REPO_ROOT}/"}"
        context+="
# ${rel_path}
$(cat "${types_file}")
"
      done <<< "${types_files}"
    fi
  fi

  echo "${context}"
}

# ---------------------------------------------------------------------------
# Helper: read a single convention doc if it exists
# ---------------------------------------------------------------------------
read_convention_file() {
  local path="$1"
  if [[ -f "${REPO_ROOT}/${path}" ]]; then
    echo "
--- ${path} ---
$(cat "${REPO_ROOT}/${path}")
"
  fi
}

# ---------------------------------------------------------------------------
# Gather relevant CLAUDE.md conventions based on issue content (Tier 2)
# ---------------------------------------------------------------------------
gather_relevant_conventions() {
  local body="$1"
  local conventions=""

  # Always include root CLAUDE.md
  conventions+=$(read_convention_file "CLAUDE.md")

  # Pattern detection: which convention docs are relevant?
  local include_db=false
  local include_app=false
  local include_auth=false
  local include_analytics=false
  local include_observability=false
  local include_flags=false
  local include_server=false
  local include_components=false
  local include_tests=false

  # Detect by keywords
  if echo "${body}" | grep -qiP '(entit|schema|table|column|migration|database|drizzle|repo)'; then
    include_db=true
  fi
  if echo "${body}" | grep -qiP '(page|route|layout|api|endpoint|handler|url|path|ui|form)'; then
    include_app=true
  fi
  if echo "${body}" | grep -qiP '(auth|session|role|permission|sign[- ]?in|sign[- ]?up|clerk|webhook)'; then
    include_auth=true
  fi
  if echo "${body}" | grep -qiP '(analytics|event|track|posthog)'; then
    include_analytics=true
  fi
  if echo "${body}" | grep -qiP '(error|sentry|observability|monitor|span|performance)'; then
    include_observability=true
  fi
  if echo "${body}" | grep -qiP '(flag|feature flag|experiment|rollout|toggle)'; then
    include_flags=true
  fi
  if echo "${body}" | grep -qiP '(seam|vendor|integration|wire|sdk)'; then
    include_server=true
  fi
  if echo "${body}" | grep -qiP '(component|button|card|dialog|sidebar|modal|ui)'; then
    include_components=true
  fi
  if echo "${body}" | grep -qiP '(test|spec|fixture|e2e|playwright|vitest|accessibility|a11y)'; then
    include_tests=true
  fi

  # If nothing matched, include the most common ones
  if ! ${include_db} && ! ${include_app} && ! ${include_auth} && ! ${include_analytics} && \
     ! ${include_observability} && ! ${include_flags} && ! ${include_server} && \
     ! ${include_components} && ! ${include_tests}; then
    include_db=true
    include_app=true
    include_auth=true
    include_server=true
    include_components=true
    include_tests=true
  fi

  if ${include_db}; then conventions+=$(read_convention_file "src/server/db/CLAUDE.md"); fi
  if ${include_app}; then conventions+=$(read_convention_file "src/app/CLAUDE.md"); fi
  if ${include_auth}; then conventions+=$(read_convention_file "src/server/auth/CLAUDE.md"); fi
  if ${include_analytics}; then conventions+=$(read_convention_file "src/server/analytics/CLAUDE.md"); fi
  if ${include_observability}; then conventions+=$(read_convention_file "src/server/observability/CLAUDE.md"); fi
  if ${include_flags}; then conventions+=$(read_convention_file "src/server/flags/CLAUDE.md"); fi
  if ${include_server}; then conventions+=$(read_convention_file "src/server/CLAUDE.md"); fi
  if ${include_components}; then conventions+=$(read_convention_file "src/components/CLAUDE.md"); fi
  if ${include_tests}; then conventions+=$(read_convention_file "tests/CLAUDE.md"); fi

  echo "${conventions}"
}

# ---------------------------------------------------------------------------
# Parse readiness status from agent output
# ---------------------------------------------------------------------------
parse_readiness_status() {
  local output="$1"

  if echo "${output}" | grep -qP 'READINESS_STATUS:\s*READY'; then
    echo "ready"
  elif echo "${output}" | grep -qP 'READINESS_STATUS:\s*NEEDS_DETAIL'; then
    echo "needs_detail"
  elif echo "${output}" | grep -qP 'READINESS_STATUS:\s*NEEDS_BREAKDOWN'; then
    echo "needs_breakdown"
  else
    log "Warning: Could not parse READINESS_STATUS. Defaulting to needs_detail."
    echo "needs_detail"
  fi
}

# ---------------------------------------------------------------------------
# Create a single child issue (called from create_child_issues)
# ---------------------------------------------------------------------------
create_single_issue() {
  local title="$1"
  local body="$2"
  local deps="$3"
  local seq="$4"

  local issue_body="## Parent Brief

Part of #${ISSUE_NUMBER}: ${ISSUE_TITLE}

## Implementation Details

${body}

---
_Created by \`scripts/triage.sh\` from the approved decomposition of #${ISSUE_NUMBER}._"

  log "Creating issue: ${title}..."

  local new_issue_url
  new_issue_url=$(gh issue create \
    --title "${title}" \
    --body "${issue_body}" \
    2>&1) || {
    log_error "Failed to create issue: ${title}"
    return 1
  }

  local new_issue_number
  new_issue_number=$(echo "${new_issue_url}" | grep -oP '[0-9]+$' || echo "")

  if [[ -z "${new_issue_number}" ]]; then
    log_error "Could not extract issue number from: ${new_issue_url}"
    return 1
  fi

  log "Created issue #${new_issue_number}: ${title}"

  # Determine if this issue has dependencies
  local has_deps=false
  if [[ -n "${deps}" && "${deps}" != "None" && "${deps}" != "none" ]]; then
    has_deps=true
  fi

  # Label the issue
  if [[ "${has_deps}" == true ]]; then
    gh issue edit "${new_issue_number}" --add-label "blocked" 2>/dev/null || true
    log "Issue #${new_issue_number} labeled 'blocked' (has dependencies: ${deps})."
  else
    gh issue edit "${new_issue_number}" --add-label "ready-for-agent" 2>/dev/null || true
    log "Issue #${new_issue_number} labeled 'ready-for-agent'."
  fi

  # Accumulate the summary for the parent comment
  created_issues+="- #${new_issue_number}: ${title}"
  if [[ "${has_deps}" == true ]]; then
    created_issues+=" (blocked by: ${deps})"
  else
    created_issues+=" (\`ready-for-agent\`)"
  fi
  created_issues+=$'\n'
}

# ===========================================================================
# Tier 1 — Intake (Product Brief Decomposition)
# ===========================================================================
run_intake() {
  log "Running Tier 1 — Intake..."

  log "Gathering codebase context..."
  local codebase_context
  codebase_context=$(gather_codebase_context)

  local intake_prompt
  intake_prompt="You are an intake agent for the Agentic Harness. Your job is to read a product-level brief and propose a decomposition into implementation-level issues.

## Product Brief — Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}

## Codebase Context

${codebase_context}

## Instructions

1. Read the product brief carefully. Understand the user outcomes it describes.
2. Read the codebase context: CLAUDE.md convention docs, existing schema, routes, and seam interfaces.
3. Decompose the brief into the smallest set of implementation issues that, when completed, fully deliver the described product capability.
4. Each issue must map to a pattern documented in the CLAUDE.md convention docs (entity, page, role, seam wiring, analytics event, feature flag, etc.).
5. Order issues by dependency — earlier issues must not depend on later ones.
6. If the brief requires a pattern NOT covered by existing conventions, flag it explicitly.

## Output Format

You MUST output your decomposition in EXACTLY this structured format. This will be posted as a GitHub comment and later parsed to create child issues.

## Proposed Decomposition

**Parent Brief**: #${ISSUE_NUMBER} — ${ISSUE_TITLE}
**Issues Proposed**: <count>

### Issue 1: <title>

**Convention**: <which CLAUDE.md convention this follows, e.g., \"src/server/db/CLAUDE.md — Adding an Entity\">
**Summary**: <one-line description of what this issue produces>
**Dependencies**: <comma-separated list of issue numbers from this decomposition, or \"None\">
**Key Parameters**:
- <parameter 1>: <value>
- <parameter 2>: <value>

**Description**:
<2-4 sentences describing what the implementation agent should do. Reference specific file paths, interfaces, and conventions.>

**Definition of Done**:
- [ ] Linter clean (\`npm run lint\` passes)
- [ ] Tests pass (\`npm run test\` passes)
- [ ] Types check (\`npx tsc --noEmit\` passes)
<additional criteria specific to this issue>
- [ ] PR description links to parent brief #${ISSUE_NUMBER}

---

### Issue 2: <title>
<same format>

---

<repeat for all issues>

## Rules

- Every issue must have a Definition of Done section.
- For UI issues, add: \`- [ ] Accessibility audit clean (axe-core AA, zero violations)\`
- Dependencies must reference other issues in THIS decomposition by number (e.g., \"Issue 1\").
- If a pattern is not covered by existing conventions, add a note: \`**Convention Gap**: <description of what is missing>\`
- Keep the total number of issues minimal. Prefer fewer, well-scoped issues over many tiny ones.
- Each issue should be independently dispatchable once its dependencies are met.

## End your output with:

> **Awaiting approval.** Reply with \"approved\" or add the \`decomposition-approved\` label to create these issues."

  local agent_output=""

  if [[ "${TRIAGE_DRY_RUN:-}" == "1" ]]; then
    log "DRY RUN: Skipping intake agent invocation."
    agent_output="## Proposed Decomposition

**Parent Brief**: #${ISSUE_NUMBER} — ${ISSUE_TITLE}
**Issues Proposed**: 1

### Issue 1: [Dry run] Placeholder issue

**Convention**: N/A (dry run)
**Summary**: Placeholder for dry run testing
**Dependencies**: None
**Key Parameters**:
- scope: dry-run

**Description**:
This is a dry run placeholder. No real decomposition was performed.

**Definition of Done**:
- [ ] Linter clean (\`npm run lint\` passes)
- [ ] Tests pass (\`npm run test\` passes)
- [ ] Types check (\`npx tsc --noEmit\` passes)
- [ ] PR description links to parent brief #${ISSUE_NUMBER}

---

> **Awaiting approval.** Reply with \"approved\" or add the \`decomposition-approved\` label to create these issues."
  else
    log "Invoking intake agent..."
    agent_output=$(claude --dangerously-skip-permissions \
      --print \
      --output-format text \
      --max-turns 20 \
      -p "${intake_prompt}" \
      2>&1) || {
      log "Warning: Intake agent exited with non-zero status."
    }
  fi

  # Validate the output contains a decomposition
  if ! echo "${agent_output}" | grep -q "## Proposed Decomposition"; then
    log_error "Intake agent did not produce a valid decomposition."

    local fail_body="## Intake Failed

The intake agent could not produce a valid decomposition for this product brief.

**What was attempted**: The agent read the brief and codebase context but did not output a structured decomposition.

**What human judgment is needed**: Please review the brief for clarity. Consider whether it describes user outcomes in enough detail for the intake agent to map to implementation patterns.

---
_Posted by \`scripts/triage.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

    gh issue comment "${ISSUE_NUMBER}" --body "${fail_body}"
    gh issue edit "${ISSUE_NUMBER}" --add-label "escalated"
    exit 1
  fi

  # Post the decomposition as a comment
  log "Posting decomposition comment..."

  gh issue comment "${ISSUE_NUMBER}" --body "${agent_output}

---
_Posted by \`scripts/triage.sh\` (Tier 1 — Intake) at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  # Remove needs-triage label if present (triage done, awaiting approval)
  if echo "${ISSUE_LABELS}" | grep -q "^needs-triage$"; then
    gh issue edit "${ISSUE_NUMBER}" --remove-label "needs-triage" 2>/dev/null || true
  fi

  log "Intake complete. Decomposition posted. Awaiting human approval."
}

# ===========================================================================
# Tier 2 — Readiness (Implementation Issue Evaluation)
# ===========================================================================
run_readiness() {
  log "Running Tier 2 — Readiness..."

  local relevant_conventions
  relevant_conventions=$(gather_relevant_conventions "${ISSUE_BODY}")

  local readiness_prompt
  readiness_prompt="You are a readiness evaluator for the Agentic Harness. Your job is to determine whether an implementation-level issue has enough detail for an agent to dispatch without questions.

## Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}

## Relevant Convention Docs

${relevant_conventions}

## Instructions

Evaluate the issue against the relevant directory conventions. An issue is ready for dispatch when an implementation agent can:
1. Understand exactly what to build from the issue description alone.
2. Know which files to create/modify based on the convention docs.
3. Know what tests to write.
4. Know when it is done (Definition of Done is present and specific).

## Evaluation Criteria

Check each of these against the relevant CLAUDE.md conventions:

1. **Scope clarity**: Is the issue about one coherent change? Or does it bundle multiple concerns?
2. **Convention mapping**: Does the issue map to a documented pattern (entity, page, role, seam wiring, etc.)? Which one?
3. **Key parameters specified**: Are the key parameters for the pattern provided? (entity fields, route paths, role names, event properties, etc.)
4. **Dependencies declared**: Are dependencies on other issues or existing code clearly stated?
5. **Definition of Done present**: Does the issue include a mechanical checklist (linter, tests, types, a11y)?
6. **No ambiguity requiring clarification**: Could an agent execute this without asking questions?

## Output Format

You MUST output your evaluation in EXACTLY this format:

READINESS_STATUS: READY | NEEDS_DETAIL | NEEDS_BREAKDOWN

### Assessment

<1-3 sentence summary of the readiness evaluation>

### Convention Match

**Pattern**: <which CLAUDE.md pattern this maps to, or \"None identified\">
**Directory**: <primary directory affected>

### Gaps Found

<If NEEDS_DETAIL: list specific missing inputs>
<If NEEDS_BREAKDOWN: explain why and propose sub-issues>
<If READY: \"No gaps found.\">

### Suggested Definition of Done

<If the issue is missing a Definition of Done, propose one. If it already has one, confirm it is sufficient or suggest additions.>

## Rules

- Be strict. An agent should NEVER need to ask a clarifying question.
- If the issue mentions implementation details but is vague about what specifically to build, mark NEEDS_DETAIL.
- If the issue covers multiple independent concerns (e.g., \"add entity AND create page AND wire seam\"), mark NEEDS_BREAKDOWN.
- A single well-scoped issue that touches multiple files (e.g., schema + repo + API route for one entity) is fine — that is the \"Adding an Entity\" pattern.
- If a Definition of Done is missing, always propose one."

  local agent_output=""

  if [[ "${TRIAGE_DRY_RUN:-}" == "1" ]]; then
    log "DRY RUN: Skipping readiness agent invocation."
    agent_output="READINESS_STATUS: READY

### Assessment

Dry run — auto-classifying as ready.

### Convention Match

**Pattern**: N/A (dry run)
**Directory**: N/A

### Gaps Found

No gaps found.

### Suggested Definition of Done

- [ ] Linter clean
- [ ] Tests pass
- [ ] Types check"
  else
    log "Invoking readiness agent..."
    agent_output=$(claude --dangerously-skip-permissions \
      --print \
      --output-format text \
      --max-turns 10 \
      -p "${readiness_prompt}" \
      2>&1) || {
      log "Warning: Readiness agent exited with non-zero status."
    }
  fi

  # Parse the readiness status
  local readiness_status
  readiness_status=$(parse_readiness_status "${agent_output}")
  log "Readiness status: ${readiness_status}"

  # Post the evaluation as a comment
  gh issue comment "${ISSUE_NUMBER}" --body "## Readiness Evaluation

**Status**: \`${readiness_status}\`

${agent_output}

---
_Posted by \`scripts/triage.sh\` (Tier 2 — Readiness) at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  # Apply labels based on status
  case "${readiness_status}" in
    ready)
      gh issue edit "${ISSUE_NUMBER}" --add-label "ready-for-agent"
      if echo "${ISSUE_LABELS}" | grep -q "^needs-triage$"; then
        gh issue edit "${ISSUE_NUMBER}" --remove-label "needs-triage" 2>/dev/null || true
      fi
      log "Issue #${ISSUE_NUMBER} labeled 'ready-for-agent'."
      ;;
    needs_detail|needs_breakdown)
      if ! echo "${ISSUE_LABELS}" | grep -q "^needs-triage$"; then
        gh issue edit "${ISSUE_NUMBER}" --add-label "needs-triage"
      fi
      log "Issue #${ISSUE_NUMBER} flagged: ${readiness_status}. Details in comment."
      ;;
  esac

  log "Readiness evaluation complete."
}

# ===========================================================================
# Approval handler — Create child issues from approved decomposition
# ===========================================================================
create_child_issues() {
  log "Creating child issues from approved decomposition..."

  local issue_count=0
  created_issues=""

  # Use a temporary file for line-by-line parsing
  local tmpfile
  tmpfile=$(mktemp)
  echo "${DECOMPOSITION_COMMENT}" > "${tmpfile}"

  local current_title=""
  local current_body=""
  local current_deps=""
  local in_issue=false
  local issue_seq=0

  while IFS= read -r line; do
    # Detect start of a new issue block
    if echo "${line}" | grep -qP '^### Issue \d+:'; then
      # Save the previous issue if we had one
      if [[ -n "${current_title}" ]]; then
        create_single_issue "${current_title}" "${current_body}" "${current_deps}" "${issue_seq}"
        issue_count=$((issue_count + 1))
      fi

      # Start a new issue
      current_title=$(echo "${line}" | sed 's/^### Issue [0-9]*: //')
      current_body=""
      current_deps=""
      in_issue=true
      issue_seq=$((issue_seq + 1))
      continue
    fi

    # Detect end markers
    if echo "${line}" | grep -q "^> \*\*Awaiting approval"; then
      break
    fi
    if echo "${line}" | grep -q "_Posted by"; then
      break
    fi

    # Accumulate body for the current issue
    if [[ "${in_issue}" == true ]]; then
      # Extract dependencies for later linking
      if echo "${line}" | grep -qP '^\*\*Dependencies\*\*:'; then
        current_deps=$(echo "${line}" | sed 's/.*\*\*Dependencies\*\*: //')
      fi
      current_body+="${line}
"
    fi
  done < "${tmpfile}"

  # Save the last issue
  if [[ -n "${current_title}" ]]; then
    create_single_issue "${current_title}" "${current_body}" "${current_deps}" "${issue_seq}"
    issue_count=$((issue_count + 1))
  fi

  rm -f "${tmpfile}"

  if [[ ${issue_count} -eq 0 ]]; then
    log_error "No issues could be parsed from the decomposition comment."
    gh issue comment "${ISSUE_NUMBER}" --body "## Child Issue Creation Failed

Could not parse individual issues from the decomposition comment. Please check the decomposition format.

---
_Posted by \`scripts/triage.sh\` at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"
    exit 1
  fi

  # Post a summary comment on the parent brief
  gh issue comment "${ISSUE_NUMBER}" --body "## Child Issues Created

**${issue_count} implementation issues** created from the approved decomposition.

${created_issues}
All dispatch-ready issues have been labeled \`ready-for-agent\`.

---
_Posted by \`scripts/triage.sh\` (approval handler) at $(date -u '+%Y-%m-%dT%H:%M:%SZ')_"

  # Add decomposition-approved label to mark the brief as processed
  gh issue edit "${ISSUE_NUMBER}" --add-label "decomposition-approved" 2>/dev/null || true

  log "Created ${issue_count} child issues from decomposition."
}

# ===========================================================================
# MAIN — Parse arguments, read issue, route to handler
# ===========================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --approve)
      APPROVE_MODE=true
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

if ! [[ "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
  log_error "Issue number must be numeric, got: ${ISSUE_NUMBER}"
  exit 1
fi

# Verify gh CLI is authenticated
if ! gh auth status >/dev/null 2>&1; then
  log_error "GitHub CLI (gh) is not authenticated. Run 'gh auth login' first."
  exit 1
fi

# Read issue metadata
log "=== Triage starting for issue #${ISSUE_NUMBER} ==="

ISSUE_JSON=$(gh issue view "${ISSUE_NUMBER}" --json title,body,labels,state,comments)

ISSUE_STATE=$(echo "${ISSUE_JSON}" | jq -r '.state')
if [[ "${ISSUE_STATE}" != "OPEN" ]]; then
  log_error "Issue #${ISSUE_NUMBER} is not open (state: ${ISSUE_STATE})."
  exit 1
fi

ISSUE_TITLE=$(echo "${ISSUE_JSON}" | jq -r '.title')
ISSUE_BODY=$(echo "${ISSUE_JSON}" | jq -r '.body')
ISSUE_LABELS=$(echo "${ISSUE_JSON}" | jq -r '.labels[].name' 2>/dev/null || echo "")

log "Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}"

# Determine tier or handle approval
if [[ "${APPROVE_MODE}" == true ]]; then
  log "Approval mode: creating child issues from decomposition."

  if ! echo "${ISSUE_LABELS}" | grep -q "^product-brief$"; then
    log_error "Issue #${ISSUE_NUMBER} is not labeled 'product-brief'. --approve only works on product briefs."
    exit 1
  fi

  DECOMPOSITION_COMMENT=$(echo "${ISSUE_JSON}" | jq -r '
    [.comments[] | select(.body | contains("## Proposed Decomposition"))] | last | .body // empty
  ')

  if [[ -z "${DECOMPOSITION_COMMENT}" ]]; then
    log_error "No decomposition comment found on issue #${ISSUE_NUMBER}. Run triage first."
    exit 1
  fi

  TIER="approve"
else
  TIER=""

  # Tier 1 check: explicit product-brief label
  if echo "${ISSUE_LABELS}" | grep -q "^product-brief$"; then
    TIER="intake"
    log "Tier 1 (Intake): Issue is labeled 'product-brief'."
  fi

  # Tier 1 check: auto-detect product-level language
  if [[ -z "${TIER}" ]]; then
    TIER=$(detect_issue_tier "${ISSUE_BODY}")
  fi

  # Default to readiness (Tier 2)
  if [[ -z "${TIER}" ]]; then
    TIER="readiness"
    log "Tier 2 (Readiness): Issue appears to be implementation-level."
  fi
fi

# Route to the correct handler
case "${TIER}" in
  intake)
    run_intake
    ;;
  readiness)
    run_readiness
    ;;
  approve)
    create_child_issues
    ;;
  *)
    log_error "Unknown tier: ${TIER}"
    exit 1
    ;;
esac

log "=== Triage complete for issue #${ISSUE_NUMBER} ==="
