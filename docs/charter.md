# Agentic Harness Charter

**Version 1.1** · April 2026

---

## 1. Purpose

The Agentic Harness is a reusable scaffolding system for piloting product builds using unsupervised AI agents. It is not a framework, not a boilerplate, and not a CLI wrapper. It is the operating environment — the rules, sensors, guides, isolation boundaries, and interaction protocols — that make it possible for AI agents to pick up GitHub Issues, execute them in isolation, produce pull requests, review each other's work, and ship. Humans review at the PR level only. They do not supervise individual commits, do not babysit agent sessions, and do not intervene unless an agent explicitly requests escalation.

Supervised use — a developer working alongside Claude Code interactively — is a valid fallback the same infrastructure supports. But it is not the design target. The design target is: a product person describes what they want in plain language, agents figure out how to build it, and humans review output.

The human interacts at the product level, not the implementation level. You do not file "add entity Invitation with fields email, role, status" — you file "users need to invite team members and manage permissions." An intake agent reads your brief, reads the codebase and its convention docs, and proposes a decomposition into implementation-level issues. You review the plan, approve it, and agents execute it.

The primary interaction canvas is GitHub. Project boards and Issues are the developer's interface. The developer's job is to write product-level briefs describing what users need, review the intake agent's proposed decomposition, and review the PRs that agents produce. Agents do everything else: decompose briefs into implementation tasks, pick up issues, run in isolation, produce PRs, review each other, iterate, and ship.

Bootstrap itself is expressed as issues. When you stand up a new project, the harness files a set of product-level briefs ("the app needs authentication," "there should be a dashboard behind auth," "we need a public landing page") and processes them through the same intake → dispatch → review pipeline that every subsequent feature uses. This means the pipeline is validated from day one, and the bootstrap issues serve as living examples of how to feed the system.

---

## 2. Stack Baseline

The stack is locked. These are not suggestions. Every project bootstrapped by this harness ships with exactly this stack, and deviations require an Architecture Decision Record in `docs/decisions/` before any code is written.

**Framework and UI.** Next.js with the App Router. React. shadcn/ui for components. Tailwind for styling. `next-themes` for theme switching. This combination was chosen because it is the most agent-legible modern web stack — the file-system routing is deterministic, the component library is copy-paste-friendly (no opaque node_modules to navigate), and the styling system is atomic and greppable.

**Data layer.** Zod for validation at every boundary. Drizzle as the ORM — chosen for its SQL-forward design, which agents can reason about without abstraction-layer guessing. `@t3-oss/env-nextjs` for typed environment variables. TanStack Query for server-state management on the client. `react-hook-form` with `zodResolver` for form handling. Every data path from user input to database row is typed end-to-end with Zod as the single source of truth for shapes.

**Authentication.** Clerk. Session management, role-based access, organization support, and webhook-driven lifecycle events. Clerk is the auth vendor seam — its SDK never appears outside `src/server/auth/`.

**Observability.** Sentry for error tracking and performance monitoring. PostHog for product analytics and feature flags. Vercel Analytics for web vitals. `@next/bundle-analyzer` for build-time bundle auditing. The structured JSON logger (`src/lib/logger.ts`) is the single internal interface for all runtime logging — console.log calls in application code are a linter error.

**Testing.** Vitest for unit and integration tests. Playwright with axe-core for end-to-end and accessibility testing. MSW for network mocking in tests (never in production code). Faker for synthetic data. Deterministic fixtures and seeds in `tests/seeds/` for reproducible test environments.

**Linting and code quality.** ESLint with Prettier. `eslint-plugin-jsx-a11y` for accessibility. Custom per-seam linters that enforce vendor containment — e.g., a lint rule that errors on Clerk imports outside `src/server/auth/`. Gitleaks for secret detection. Commitlint for conventional commits. These are not style preferences; they are the mechanical enforcement layer that makes unsupervised operation safe.

**Notifications.** Sonner for toast notifications. shadcn Dialog for modal interactions.

**Dev environment.** Docker Compose running Postgres and Mailpit. The dev environment is fully local and fully reproducible — no shared staging databases, no remote services required for local development.

**Deployment.** Vercel with preview environments per branch. Every PR gets a preview URL. CI/CD is configured from the first commit.

**Dependencies.** Renovate for automated dependency updates, configured with a merge schedule and auto-merge for patch-level updates that pass CI.

---

## 3. Vendor Seams

Vendor seams are architecturally load-bearing. This is the single most important structural decision in the harness, and it is non-negotiable.

Every third-party integration is confined to a canonical module with a stable internal interface. The rest of the application imports the interface, never the vendor SDK. A custom ESLint rule per seam enforces this boundary — importing `@clerk/nextjs` outside `src/server/auth/` is a build-breaking error, not a warning.

The principle: every decision has a default, and every default lives behind a seam. Vendors are chosen because they are good defaults. They are not permanent commitments. The seam makes swapping vendors a bounded task — change the implementation inside the seam module, run the test suite, ship.

**Day-one seams:**

`src/server/auth/` — Authentication. Default: Clerk. Exports session utilities, role checks, middleware, webhook handlers. No Clerk types leak into the rest of the application; auth functions return plain objects conforming to the seam's own TypeScript interfaces.

`src/server/analytics/` — Product analytics. Default: PostHog. Exports typed event-tracking functions. Event names and properties are defined as a TypeScript union — the analytics seam is a typed catalog, not a bag of strings.

`src/server/observability/` — Error tracking and performance. Default: Sentry. Exports error-capture and span-creation utilities. Application code never calls `Sentry.captureException` directly.

`src/server/flags/` — Feature flags. Default: PostHog feature flags. Exports flag-evaluation functions with typed flag names. Flag state is server-resolved by default; client-side flag evaluation is opt-in per flag.

`src/server/db/` — Database. Default: Drizzle with Postgres. Exports the database client, schema definitions, and migration utilities. Drizzle's schema files live here. No raw SQL outside this module except in migration files.

`src/lib/logger.ts` — Structured logging. Default: structured JSON to stdout. Exports a logger with level methods (`info`, `warn`, `error`, `debug`) and structured context. The logger is the only module that lives outside the `src/server/` seam directory because it is used on both server and client paths.

**Seams added via feature issues:** Billing (`src/server/billing/`, default Stripe), email (`src/server/email/`, default Resend), storage (`src/server/storage/`, default S3-compatible), search (`src/server/search/`), and others as the product requires. Each new seam is introduced through the intake process — a product-level brief triggers decomposition that includes the seam's interface contract, default vendor, linter rule, and test fixtures.

---

## 4. Agent Identity

Agents in the harness inhabit distinct roles. They are not general-purpose assistants. Each role has a defined input, a defined output, and a bounded scope of authority.

**The intake agent** receives a product-level brief — written in the language of users and outcomes, not implementations — and translates it into a set of implementation-level issues. It reads the codebase (schema, existing seams, current routes, CLAUDE.md tree) to understand what exists, what patterns have been established, and what conventions govern each directory. Its output is a comment on the brief issue listing the proposed child issues, each with enough implementation detail for a dispatched agent to execute without clarification. The intake agent does not write code. It plans. Its quality is measured by whether the implementation issues it produces are dispatch-ready without further clarification.

**The implementation agent** is a senior engineer on a team of one, executing a well-scoped implementation issue in isolation, producing a PR that will be reviewed by a peer. Its operating context is fully defined by three things: the issue description (which is the spec), the CLAUDE.md file tree (which is the codebase's operating manual), and the codebase itself (which the agent reads before it writes). The implementation agent does not ask clarifying questions of a human during execution. If the issue is ambiguous enough to require clarification, the issue is malformed — the agent kicks it back via a comment explaining what is missing, and it stops. The agent's output is exactly one PR linked to exactly one issue, containing the smallest viable diff that resolves the issue. When the agent is the first to implement a pattern in a directory (the first entity, the first page, the first seam wiring), the PR includes an update to that directory's CLAUDE.md — evolving it from prescriptive cold-start instructions to a pattern reference citing the concrete implementation as an example.

**The review agent** evaluates a PR against the linked issue spec, codebase conventions, and mechanical checks. It is a fresh session with no memory of the authoring process — it evaluates the output, not the reasoning. Its output is a structured review posted as a PR comment, and the review cycle continues until approval or escalation.

All agents treat linter errors as prompts. When a linter fails, the error message is a remediation hint. Agents read errors, apply fixes, and re-run. They do not suppress warnings, disable rules, or work around enforcement.

All agents checkpoint by posting progress updates as comments on the GitHub issue or PR they are working on. The issue is the session log. There are no local session logs that disappear when the environment is torn down.

---

## 5. Operating Principles

These principles are grouped into three categories borrowed from Martin Fowler's harness engineering taxonomy: Operation (how agents do work), Regulation (how the system ensures quality), and Evolution (how the harness improves itself over time).

### Operation

**Product briefs in, PRs out.** The human writes in the language of users and outcomes. The intake agent translates to implementation. The implementation agent produces code. The review agent validates quality. This pipeline means a product person can drive development without writing technical specs — and an engineer can drive it faster by writing briefs at whatever level of detail they prefer, because the intake agent fills in the implementation specifics either way.

**Spec before code, decomposed depth-first.** The issue description is the spec. There is no separate design document, no Notion page, no Slack thread that the agent needs to find. If the information isn't in the issue, it doesn't exist for the agent. Product briefs are decomposed depth-first by the intake agent: a large brief becomes smaller implementation issues, each independently dispatchable.

**Read before write.** An agent reads the files it intends to modify before modifying them. It reads CLAUDE.md and relevant subdirectory CLAUDE.md files before starting work. It reads the schema before writing a migration. It reads the existing tests before writing new ones. It never guesses parameters, file contents, function signatures, or configuration values.

**Smallest viable diff.** One issue, one PR, one coherent change. If an implementation issue requires changes across multiple concerns, the intake agent decomposed it wrong and it should be re-triaged. The smallest viable diff is not the smallest possible diff — it includes tests, type updates, documentation changes, and migration files. It is the smallest diff that leaves the codebase in a fully consistent state.

**Working isolation is mandatory.** Every `/dispatch` spawns a fresh git worktree, a fresh Docker container, and a fresh database seeded from `tests/seeds/`. The agent's blast radius is one disposable environment. It cannot corrupt the main branch, cannot interfere with other dispatched agents, and cannot leave behind state that affects future dispatches.

**The issue is the session log.** Agents post progress updates as comments on the GitHub issue they are executing. When the environment is torn down, the issue retains the full record of what happened. There are no local session logs.

### Regulation

**Mechanical enforcement over documentation.** Markdown warns of nothing. Linters gate. Every invariant that matters is enforced by a tool — a linter rule, a pre-commit hook, a CI check, a type constraint. Documentation explains why an invariant exists and how to work with it. But the gate is mechanical. An agent cannot accidentally violate vendor-seam containment because the linter will not let the code compile.

**Sensors write back with remediation hints.** Linter errors, type errors, test failures — these are not opaque failures. They are messages to the agent. Every custom linter rule includes an error message that explains what is wrong and suggests a fix. The agent reads these messages as instructions.

**The application is a sensor.** Chrome DevTools MCP, Playwright, structured JSON logs, and Mailpit (for email flows) are all observation surfaces. The agent does not fly blind after writing code — it runs the application, observes the output, and validates its work against the spec.

**Agent-to-agent review is the primary quality gate.** After an implementation agent produces a PR, a review agent reviews it via `/review`. The review is not ceremonial — it checks correctness, adherence to conventions, test coverage, and whether the PR actually resolves the issue. Multi-pass review continues until the reviewer approves or until the bounded retry limit (default N=5) is reached. If agents cannot converge, the PR is escalated via a comment requesting human review. Agents never silently fail or silently succeed.

**Human review happens at the PR level only.** Humans see output, not process. They review the PR diff, the PR description, the linked issue, the CI results, and the preview deployment. They do not review individual commits, do not monitor agent sessions, and do not provide mid-execution guidance.

**CI budget is generous but bounded.** A dispatched agent gets generous CI cycles per task (default: 5 rounds of push-fix-push). If it cannot produce a green build within that budget, it escalates. The budget prevents infinite loops while giving agents enough room to self-correct.

**Dispatch legibility is strict.** An implementation agent must be able to execute an issue without asking clarifying questions. If it cannot, the issue is malformed — either the intake agent produced an incomplete decomposition, or someone filed an implementation issue manually without enough detail. The agent comments on the issue explaining what is missing and stops. This strictness is a feature — it forces the intake layer to produce complete specs.

### Evolution

**Enforce invariants, not implementations.** The harness specifies what must be true (vendor imports stay inside seams, tests pass, types check, accessibility scores meet thresholds) but not how agents achieve it. This leaves room for agents to find better implementations within the constraints.

**When the agent struggles, ask what capability is missing.** The diagnostic frame is not "what did the agent do wrong?" but "what tool, rule, context, gate, documentation, or legibility surface is missing?" Agent failure is a signal about the harness, not about the agent.

**Garbage collect continuously.** A GC sweeper runs periodically to identify dead code, stale documentation, unused dependencies, and drifting conventions. It updates `docs/quality-score.md` and `docs/generated/harness-metrics.md`. It can produce auto-refactor PRs for mechanical cleanup.

**Progressive disclosure, conditional rules.** CLAUDE.md at the root is a table of contents, not an encyclopedia. Subdirectory CLAUDE.md files contain rules scoped to that directory. An agent working in `src/server/auth/` reads the auth-specific rules; it does not need to internalize billing rules. This keeps context windows focused and rules precise.

**Contain the LLM in deterministic wrappers.** Commands and hooks are the blueprint primitive. A `/dispatch` command is a deterministic sequence (verify preconditions → create worktree → seed DB → hand off to agent → collect PR → trigger review) with agentic steps at defined points. The overall flow is predictable; the agent's contribution is the creative work within each step.

**Bootstrap is dogfood.** The act of bootstrapping a new project is itself expressed as product-level briefs flowing through the intake → dispatch → review pipeline. "The app needs authentication" is an issue, not a manual phase. This validates the pipeline from its first use and produces a library of example issues that demonstrate how to feed the system. There is no separate "bootstrap procedure" that bypasses the pipeline — if the pipeline cannot bootstrap a project, the pipeline is not ready.

**Conventions are prescriptive from day one.** Each directory's CLAUDE.md contains concrete, actionable guidance for how to add things in that directory — file naming, interface shapes, test expectations, linter gates. On a fresh codebase, these convention docs serve as the cold-start reference the intake agent decomposes against. As code accumulates, the conventions can reference existing implementations as examples. The CLAUDE.md tree evolves from prescriptive instructions to pattern references naturally, without a separate system to maintain.

---

## 6. Primitive Inventory

Primitives are the named, locatable components of the harness. Each is either a **guide** (shapes agent behavior before or during execution) or a **sensor** (observes agent output and feeds back corrections). This taxonomy follows Fowler's distinction.

### Guides

**CLAUDE.md tree.** Root CLAUDE.md is the table of contents. Subdirectory CLAUDE.md files contain scoped rules. Together they form the operating manual an agent reads before starting work. Location: `CLAUDE.md` at root and in every significant subdirectory.

Each directory's CLAUDE.md is convention-forward — it tells an agent exactly how to add things in that directory. These convention docs are the intake agent's decomposition vocabulary and the implementation agent's execution guide. They cover the standard implementation patterns the harness supports:

- **Adding an entity** (`src/server/db/CLAUDE.md`): Drizzle schema file at `schema/<name>.ts`, migration via `drizzle-kit generate`, repo layer at `repos/<name>.ts` with typed CRUD functions, API route handler at `app/api/<name>/route.ts` with Zod validation, tests.
- **Adding a role** (`src/server/auth/CLAUDE.md`): Clerk role configuration, permission guards, route guarding, integration tests.
- **Adding a page** (`src/app/CLAUDE.md`): Route file placement, data binding, SEO metadata, loading/error states, Playwright + axe-core test.
- **Adding a vendor seam** (`src/server/CLAUDE.md`): Directory structure, interface contract, stub implementation, custom ESLint rule, test fixtures.
- **Wiring a seam** (`src/server/CLAUDE.md`): Replacing a stub with a live vendor SDK, implementing the interface, integration tests, env var additions.
- **Adding analytics events** (`src/server/analytics/CLAUDE.md`): Event definition in typed catalog, Zod properties schema, trigger wiring, verification.
- **Adding feature flags** (`src/server/flags/CLAUDE.md`): Flag declaration, type, default value, gated code paths, rollout plan in `docs/decisions/`.

On a fresh codebase, these docs are detailed and prescriptive — they specify exact file paths, interface shapes, and test patterns. As code accumulates, they evolve to reference existing implementations as examples ("follow the pattern established by `users` and `projects`"). The convention docs and the codebase converge into a single source of truth, with no separate system to maintain.

**Commands.** Named entry points that orchestrate deterministic-then-agentic workflows:

- `/triage <issue-number>` — The intake and readiness system. Two-tier: if the issue is a product-level brief, the intake agent reads the codebase and the CLAUDE.md convention docs, proposes a decomposition into implementation issues, and posts it as a comment for human approval. If the issue is already an implementation-level task, the readiness tier evaluates whether it has enough detail for dispatch and either labels it `ready-for-agent`, flags missing inputs, or proposes further breakdown.
- `/dispatch <issue-number>` — The execution entry point. Verifies preconditions (issue exists, is labeled `ready-for-agent`, has no unresolved blockers), spawns an isolated environment (git worktree at `.worktrees/issue-<number>`, Docker container `dispatch-<issue-number>`, Postgres database `dispatch_<issue_number>` seeded from `tests/seeds/`), hands the issue to an implementation agent, collects the PR, links PR to issue, triggers review. Cleanup is automatic on exit. Location: orchestrated by `scripts/dispatch.sh`.
- `/review <pr-number>` — A review agent evaluates a PR against the linked issue spec, codebase conventions, and mechanical checks. Multi-pass until approval or escalation.
- `/bootstrap <project-name>` — Creates a new project from scratch: GitHub repo, Project board, harness infrastructure (CI, linters, hooks, CLAUDE.md tree), stack scaffolding (Next.js, seam stubs, Docker), and then files the bootstrap product briefs as issues. Those briefs ("the app needs authentication," "there should be a dashboard behind auth") flow through `/triage` → `/dispatch` → `/review` like any feature — validating the pipeline and producing example issues.

**Hooks.** Pre-commit and pre-push hooks that run deterministic checks before code leaves the local environment. Pre-commit: Prettier, ESLint (with seam linters), gitleaks, commitlint. Pre-push: type-check, unit tests, bundle analysis delta.

**Architecture Decision Records.** Any deviation from the locked stack or established conventions is recorded in `docs/decisions/` as an ADR with context, decision, and consequences. ADRs are guides because agents read them to understand why the codebase deviates from defaults in specific places.

**Escalation-via-comment protocol.** When agents cannot converge — whether during authoring (CI budget exhausted), review (review retry limit reached), or intake (brief too ambiguous to decompose) — they post a structured comment on the issue or PR describing what was attempted, where convergence failed, and what human judgment is needed. The issue or PR is labeled `escalated`. Agents never silently fail or silently succeed.

**Dispatch-on-label automation.** A GitHub Actions workflow (`dispatch-on-label.yml`) triggers `/dispatch` when an issue is labeled `ready-for-agent`. This is the automation entry point that closes the loop between intake approval and agent execution. Location: `.github/workflows/dispatch-on-label.yml`.

**Bootstrap brief catalog.** Six product-level briefs that `/bootstrap` files as issues on a new project, covering: authentication, dashboard shell, landing page, observability, analytics, and feature flags. These briefs describe the day-one product in user-facing terms and serve as both the bootstrap mechanism and the canonical examples of how to feed the system. Each brief is processed by the intake agent, decomposed into implementation issues, and dispatched. Location: `harness/bootstrap-briefs/`. Full brief text and expected decompositions are documented in the implementation plan (Phase 6).

### Sensors

**ESLint with custom seam rules.** One custom rule per vendor seam that errors on vendor SDK imports outside the seam module. These are the mechanical enforcement of vendor containment. Location: `eslint-rules/`.

**CI pipeline.** GitHub Actions workflows that run the full validation suite: type-check, lint, unit tests, integration tests, e2e tests, accessibility audit, bundle analysis, secret scanning. CI is the final gate before a PR can merge. Location: `.github/workflows/`.

**Playwright + axe-core.** End-to-end tests that also run accessibility audits. Every user-facing page has at least one Playwright test that asserts core functionality and passes axe-core with zero violations at the AA level. Location: `tests/e2e/`.

**Structured JSON logger.** Runtime sensor that produces machine-readable log output. Agents can grep logs to diagnose runtime behavior. Location: `src/lib/logger.ts`, output to stdout.

**Mailpit.** Local email capture for testing transactional email flows. Agents verify email content and delivery by querying Mailpit's API. Location: Docker Compose service.

**Chrome DevTools MCP.** Observation surface for UI behavior during development and testing. Agents can inspect DOM state, network requests, console output, and rendering performance.

**`docs/quality-score.md`.** Auto-generated quality dashboard updated by the GC sweeper. Tracks test coverage, type coverage, accessibility score, bundle size trend, dependency freshness, and documentation staleness. Location: `docs/quality-score.md`.

**`docs/generated/harness-metrics.md`.** Auto-generated harness health metrics: dispatch success rate, average CI rounds per dispatch, escalation rate, review convergence rate, intake decomposition accuracy, convention pattern frequency. Location: `docs/generated/harness-metrics.md`.

---

## 7. Folder Structure

This is the canonical layout at the harness level. It represents the project as it exists after bootstrap, before any feature issues have been dispatched.

```
├── .github/
│   ├── workflows/               # CI/CD pipelines, dispatch automation
│   │   ├── ci.yml               # Lint, type-check, test, a11y, bundle analysis
│   │   └── dispatch-on-label.yml # Triggers /dispatch when issue labeled ready-for-agent
│   ├── CODEOWNERS               # Review assignment rules
│   └── pull_request_template.md # PR description template
├── .husky/                      # Git hooks (pre-commit, pre-push)
├── docker/
│   ├── docker-compose.yml       # Postgres + Mailpit
│   └── Dockerfile.dev           # Dev container for isolated dispatch
├── docs/
│   ├── decisions/               # Architecture Decision Records
│   ├── generated/               # Auto-generated docs (harness-metrics.md)
│   └── quality-score.md         # Auto-updated quality dashboard
├── eslint-rules/                # Custom per-seam linter rules
├── harness/
│   └── bootstrap-briefs/        # Product-level briefs filed by /bootstrap
├── scripts/
│   ├── dispatch.sh              # Orchestrates /dispatch: worktree + container + seed
│   ├── bootstrap.sh             # Orchestrates /bootstrap: repo + app + briefs
│   └── seed.ts                  # Database seeding for dispatch environments
├── src/
│   ├── app/                     # Next.js App Router pages and layouts
│   │   ├── (auth)/              # Auth-guarded routes (dashboard shell)
│   │   ├── (marketing)/         # Public marketing pages
│   │   ├── api/                 # API route handlers
│   │   └── layout.tsx           # Root layout with providers
│   ├── components/
│   │   ├── ui/                  # shadcn/ui components
│   │   └── ...                  # App-specific components
│   ├── lib/
│   │   ├── logger.ts            # Structured JSON logger (cross-cutting seam)
│   │   └── utils.ts             # Shared utilities
│   └── server/
│       ├── auth/                # Auth seam (Clerk)
│       ├── analytics/           # Analytics seam (PostHog)
│       ├── observability/       # Observability seam (Sentry)
│       ├── flags/               # Feature flags seam (PostHog)
│       └── db/                  # Database seam (Drizzle + Postgres)
│           ├── schema/          # Drizzle schema definitions
│           └── migrations/      # Drizzle migrations
├── tests/
│   ├── e2e/                     # Playwright + axe-core tests
│   ├── integration/             # Integration tests (real DB)
│   ├── unit/                    # Vitest unit tests
│   ├── seeds/                   # Deterministic seed data for dispatch environments
│   └── fixtures/                # Shared test fixtures
├── CLAUDE.md                    # Root operating manual (TOC, not encyclopedia)
├── README.md                    # Project overview, links to charter and docs
├── drizzle.config.ts
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── vitest.config.ts
├── playwright.config.ts
├── .env.example                 # Documented env vars (never .env in repo)
├── .eslintrc.cjs
├── .prettierrc
├── commitlint.config.cjs
├── renovate.json
└── package.json
```

Every significant directory contains its own `CLAUDE.md` with rules scoped to that directory. The root `CLAUDE.md` references them by path. An agent working in `src/server/db/` reads the root CLAUDE.md (for global conventions) and `src/server/db/CLAUDE.md` (for database-specific rules). It does not need to read `src/server/auth/CLAUDE.md`.

---

## 8. Success Criteria

These criteria are measurable, opinionated, and tied to the unsupervised target. The harness is successful when:

**Dispatch success rate exceeds 80% (escalation rate under 20%).** Four out of five issues dispatched to agents result in a merged PR without human intervention beyond final PR review. The remaining 20% may require escalation, issue revision, or manual completion — but 80% flow through the pipeline end-to-end. When escalation happens, the agent's comment clearly describes what it tried, where it got stuck, and what judgment it needs from a human.

**Intake decomposition accuracy exceeds 90%.** Nine out of ten implementation issues produced by the intake agent are dispatch-ready without human revision. The remaining 10% need minor adjustments (missing field, wrong route path) — but 90% are executable as-is. This is the metric that validates the intake agent's understanding of the convention docs and codebase state.

**Average CI rounds per dispatch is under 3.** Agents self-correct within the CI budget. If the average exceeds 3, the harness is missing guides or sensors that would prevent the errors agents are making.

**Zero vendor SDK imports outside seam modules.** Enforced mechanically. The custom seam linters produce zero violations at all times. A single violation is a CI-blocking error.

**Every user-facing page passes axe-core AA with zero violations.** Accessibility is not aspirational; it is gated. Playwright tests include axe-core assertions, and they must pass for a PR to merge.

**Bootstrap to first merged feature PR in under 4 hours.** A new project goes from `/bootstrap` to a deployed preview URL with a merged feature PR in under 4 hours of wall-clock time, with no human intervention between bootstrap brief approval and PR review.

**Review convergence within 3 passes.** Agent-to-agent review resolves within 3 review-revise cycles 90% of the time. If reviews are not converging, the issue spec or the codebase conventions are underspecified.

**No orphaned environments.** Every dispatched worktree and Docker container is cleaned up after the dispatch completes, whether successfully or via escalation. The cleanup is part of the dispatch script, not a separate manual step.

**Quality score trends upward.** The auto-generated `docs/quality-score.md` shows improving or stable trends in test coverage, type coverage, accessibility compliance, bundle size, and dependency freshness over time. A sustained downward trend in any metric triggers a GC sweep.

---

*This charter is a living document versioned alongside the harness. Changes require an ADR in `docs/decisions/` before the charter is updated. The charter describes what is true and what must remain true. It does not describe aspirations.*
