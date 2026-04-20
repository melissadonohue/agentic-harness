# Agentic Harness

A reusable scaffolding system for building products with unsupervised AI agents.

The harness is the operating environment — rules, sensors, guides, isolation boundaries, and interaction protocols — that makes it possible for AI agents to pick up GitHub Issues, execute them in isolation, produce pull requests, review each other's work, and ship. Humans write product-level briefs and review PRs. Agents do everything else.

## How it works

1. A human writes a product-level brief as a GitHub Issue ("users need to invite team members and manage permissions")
2. The intake agent reads the codebase and convention docs, decomposes the brief into implementation issues
3. Implementation agents pick up issues in isolated environments, produce PRs
4. Review agents evaluate PRs against the issue spec and codebase conventions
5. Humans review the final output at the PR level

## Documentation

- **[Charter](docs/charter.md)** — What the harness is and what must remain true. The normative reference.
- **[Implementation Plan](docs/implementation_plan.md)** — How to build the harness, in what order, and how to know when each phase is done.

## Stack

Next.js (App Router) · React · shadcn/ui · Tailwind · Drizzle · Zod · Clerk · Sentry · PostHog · Vitest · Playwright · Docker

See the [charter](docs/charter.md#2-stack-baseline) for the full stack baseline and rationale.

## Status

Phase 1: Infrastructure Foundation — in progress.
