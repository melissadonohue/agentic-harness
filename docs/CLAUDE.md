# docs/ — Documentation Conventions

This directory contains all project documentation. Everything an agent needs is in the repository — no external wikis, no Notion, no Slack threads.

## Structure

- `charter.md` — The normative reference. Defines what the harness is and what must remain true. Changes require an ADR before the charter is updated.
- `implementation_plan.md` — Procedural companion to the charter. Defines how to build the harness, in what order, and exit criteria for each phase.
- `decisions/` — Architecture Decision Records (ADRs). Any deviation from the locked stack or established conventions is recorded here.
- `quality-score.md` — Auto-generated quality dashboard (created in Phase 7).
- `generated/` — Auto-generated documentation (harness metrics, created in Phase 7).

## Architecture Decision Records (ADRs)

### When to Write an ADR

Write an ADR before making any change that deviates from the charter's locked stack, introduces a new convention not covered by existing CLAUDE.md files, or overrides an existing ADR.

### ADR Format

File naming: `docs/decisions/NNNN-short-title.md` where NNNN is zero-padded sequential.

```markdown
# NNNN. Short Title

**Date**: YYYY-MM-DD
**Status**: Proposed | Accepted | Deprecated | Superseded by [NNNN]

## Context

What is the situation that requires a decision? What forces are at play?

## Decision

What is the decision and why was it chosen?

## Consequences

What are the positive, negative, and neutral consequences of this decision?
```

### Rules

- ADRs are append-only. Never edit an accepted ADR — supersede it with a new one.
- The first ADR (0001) records the charter's stack and convention decisions.
- ADRs are guides — agents read them to understand why the codebase deviates from defaults.
