# Agentic Harness Implementation Plan

**Companion to charter.md v1.1** · April 2026

---

## Relationship to the Charter

The charter is normative — it defines what the harness is and what must remain true. This plan is procedural — it defines how to build the harness, in what order, and how to know when each phase is done. Every deliverable in this plan traces to a commitment in the charter. If a deliverable contradicts the charter, the charter wins.

This plan is designed for execution in Cowork sessions with Claude. Each phase is scoped to be completable in one or two focused sessions. Phases are sequential — each depends on the output of the previous phase — but tasks within a phase can often be parallelized.

There is a deliberate chicken-and-egg in this plan. The charter says bootstrap is expressed as issues flowing through the pipeline, but the pipeline itself must be built first. Phases 1 through 5 build the harness machinery in supervised Cowork sessions. Phase 6 is the payoff: the product bootstrap — auth, dashboard, landing page, vendor seam wiring — is expressed as product-level briefs that flow through intake → dispatch → review. Everything from Phase 6 onward eats its own cooking.

---

## MVP Definition

The minimum viable harness is the smallest subset that demonstrates the full loop: a product person writes a brief, the intake agent decomposes it, implementation agents dispatch against the child issues, review agents validate the PRs, and the PRs are ready for human merge.

The MVP includes: the infrastructure foundation (CI, linters, hooks, CLAUDE.md tree), the stack scaffolding (Next.js, seam stubs, Docker) with prescriptive convention docs in every directory, the dispatch system with isolation, the agent review pipeline, the intake tier of `/triage`, and a successful run of at least one bootstrap brief through the full pipeline. That brief ("the app needs user authentication") must produce merged PRs that result in a working auth flow on the preview URL.

Everything else — GC sweepers, harness metrics, extended dogfooding — is post-MVP. Important, but not required to demonstrate the loop.

---

## Phase 1: Infrastructure Foundation

### Why

Nothing else works without the mechanical enforcement layer. Linters, hooks, CI, and the CLAUDE.md tree are the environment that makes unsupervised agents safe. Building application code before this infrastructure is in place means building without guardrails — exactly the pattern the harness exists to prevent. Scaffold precedes code.

### Deliverables

The GitHub repository, initialized with branch protections (require PR reviews, require CI to pass, no direct pushes to main), CODEOWNERS assigning review to the repository owner, and a PR template that links to issues and includes a validation checklist.

The root CLAUDE.md file, structured as a table of contents referencing subdirectory CLAUDE.md files. It covers: project purpose, stack baseline (by reference to the charter), global conventions (naming, file organization, import ordering, error handling patterns), and pointers to every subdirectory CLAUDE.md.

ESLint configuration with Prettier integration, `eslint-plugin-jsx-a11y`, and the first custom seam linter rule (a reference implementation that other seam rules will follow). Commitlint configured for conventional commits. Gitleaks configured for secret detection.

Husky hooks: pre-commit runs Prettier, ESLint, gitleaks, and commitlint. Pre-push runs type-check and unit tests.

The GitHub Actions CI workflow: type-check, lint, unit tests, integration tests (when they exist), e2e tests (when they exist), bundle analysis. The workflow runs on every PR and blocks merge on failure.

The GitHub Project board with columns: Backlog, Ready for Agent, In Progress, In Review, Done. Labels: `ready-for-agent`, `needs-triage`, `blocked`, `escalated`, `product-brief`.

The `docs/decisions/` directory with ADR-0001: "Use this stack and these conventions" — a record of the charter's stack decisions in ADR format so the pattern is established from day one.

### Exit Criteria

A commit pushed to a feature branch triggers CI. CI runs lint, type-check, and commitlint (no application code exists yet, so tests are placeholder). Pre-commit hooks run locally and catch formatting violations, secret leaks, and malformed commit messages. The CLAUDE.md tree exists and an agent reading it can understand the project's conventions without external context. The Project board exists with correct columns and labels.

### First Tasks

1. Create the GitHub repository with `.gitignore`, `LICENSE`, and initial `README.md`.
2. Initialize `package.json` with dev dependencies: ESLint, Prettier, commitlint, husky, gitleaks.
3. Write root `CLAUDE.md` and structural subdirectory CLAUDE.md files for infrastructure directories (docs, scripts, eslint-rules). Application directory convention docs are written in Phase 2 when those directories are created.
4. Write the reference seam linter rule and ESLint configuration.
5. Configure Husky hooks and commitlint.
6. Write the CI workflow in `.github/workflows/ci.yml`.
7. Configure the GitHub Project board, labels, and branch protections.
8. Write ADR-0001.
9. Validate: push a branch, confirm CI runs, confirm hooks fire locally.

### Decisions

**Monorepo or single package?** Single package. The harness targets products, not platforms. A monorepo adds tooling complexity (Turborepo, workspace configuration, cross-package type resolution) that benefits large teams but creates unnecessary navigation overhead for agents. If a product outgrows a single package, that is a future decision recorded via ADR.

**ESLint flat config or legacy config?** Legacy `.eslintrc.cjs`. Flat config is the future, but tooling support (IDE plugins, shareable configs, custom rule integration) is more reliable with legacy config as of this writing. Migrate via ADR when flat config tooling matures.

**GitHub Projects or external project management?** GitHub Projects. The harness's primary interaction surface is GitHub. Adding an external tool (Linear, Jira) creates a synchronization problem and a context problem — agents would need to read two systems. GitHub Projects keeps everything in one place.

---

## Phase 2: Stack Scaffolding

### Why

The application skeleton needs to exist before vendor seams can be wired. This phase creates the Next.js project with all configuration files, the component library, the theme system, and the folder structure defined in the charter — but without vendor integrations. The seam directories are created with their interfaces defined but implementations stubbed.

### Deliverables

Next.js project initialized with App Router, TypeScript strict mode, Tailwind, and `next-themes`. The `src/` directory structure matching the charter's folder layout. shadcn/ui initialized with the project's base components (Button, Card, Dialog, Input, Label, Select, Textarea, Toast via Sonner, and the dashboard shell layout components).

Zod, Drizzle, `@t3-oss/env-nextjs`, TanStack Query, and `react-hook-form` installed and configured. `drizzle.config.ts`, `tailwind.config.ts`, `next.config.ts`, `tsconfig.json` with path aliases, and `vitest.config.ts` all in place.

Docker Compose with Postgres and Mailpit services. A `docker/Dockerfile.dev` for the development container. Database connection configured through environment variables validated by `@t3-oss/env-nextjs`.

Mailpit documented as an agent-accessible sensor. The `docker/CLAUDE.md` file explains how agents query Mailpit's API (`http://localhost:8025/api/`) to verify email content and delivery during development and testing. Includes example patterns: list messages, search by recipient, assert email body content. This turns Mailpit from passive infrastructure into an active observation surface that implementation agents use to validate transactional email flows.

Every day-one vendor seam directory created with: a TypeScript interface file defining the seam's contract, a stub implementation that throws "not yet implemented" errors (replaced by dispatch in Phase 6), a custom ESLint rule enforcing vendor containment, and a **prescriptive CLAUDE.md** scoped to that seam. These are not placeholder docs — they are the cold-start convention reference that the intake agent decomposes against and the implementation agent executes from. Each seam's CLAUDE.md specifies: the directory's purpose and boundaries, how to wire the seam (which files to create, what interface to implement, what tests to write), how to extend it (adding events, flags, roles, etc.), and what linter gates apply. The `src/app/CLAUDE.md` covers page conventions (route placement, data binding, SEO, loading/error states, Playwright test). The `src/server/db/CLAUDE.md` covers entity conventions (schema files, migrations, repo layer, API routes). As code accumulates after bootstrap, these docs evolve from prescriptive instructions to pattern references ("follow the pattern established by `users` and `projects`").

The structured JSON logger at `src/lib/logger.ts`, fully implemented (it has no vendor dependency — it is the one seam that ships complete in this phase).

Chrome DevTools MCP configured as an agent-accessible observation surface. Agents use it to inspect DOM state, network requests, console output, and rendering performance during development and testing. Configuration documented in the root CLAUDE.md so dispatched agents know it is available.

Vitest configured and running with a single canary test. Playwright configured with axe-core integration and a single canary test that loads the dev server and asserts no accessibility violations on the root page.

The Vercel project created and linked, with preview deployments enabled. The first deployment goes live with a placeholder landing page.

### Exit Criteria

`npm run dev` starts the Next.js dev server. `docker compose up` starts Postgres and Mailpit. The dev server connects to Postgres. The placeholder landing page renders at `localhost:3000`. The Vercel preview deployment is live. `npm run test` passes the canary tests. `npm run lint` passes with all seam linter rules active (no violations because no vendor imports exist yet). Every seam directory has its interface file, stub, CLAUDE.md, and linter rule. The folder structure matches the charter. Chrome DevTools MCP is configured and documented in root CLAUDE.md. Mailpit's API usage patterns are documented in `docker/CLAUDE.md`.

### First Tasks

1. `npx create-next-app` with TypeScript, Tailwind, App Router, `src/` directory.
2. Configure `tsconfig.json` path aliases (`@/` for `src/`).
3. Install and configure shadcn/ui; add base component set.
4. Install data-layer dependencies; configure Drizzle, Zod, TanStack Query, react-hook-form.
5. Write `docker-compose.yml` with Postgres and Mailpit; write `Dockerfile.dev`.
6. Configure `@t3-oss/env-nextjs` with initial environment schema.
7. Create all day-one seam directories with interfaces, stubs, linter rules, and prescriptive CLAUDE.md convention docs (not placeholders — these are the cold-start decomposition reference).
8. Implement `src/lib/logger.ts`.
9. Configure Chrome DevTools MCP for agent use; document availability in root CLAUDE.md.
10. Configure Vitest and Playwright; write canary tests.
11. Link Vercel project; push and confirm preview deployment.

### Decisions

**Database for local dev: Dockerized Postgres or SQLite?** Dockerized Postgres. SQLite diverges from production behavior in ways that bite during migration testing (transaction semantics, JSON operators, concurrent access). The Docker overhead is marginal and the environment matches production.

**shadcn/ui component installation: all at once or on demand?** Base set up front (the components listed above), then on demand via feature issues. Installing everything creates unused code that triggers the GC sweeper. The base set covers the dashboard shell and common form patterns.

**TanStack Query or SWR?** TanStack Query. It has a more explicit cache model, better devtools, and more predictable behavior for agents reasoning about data flow. SWR's implicit revalidation can create surprising behavior that agents would need to debug.

---

## Phase 3: Dispatch System and Isolation

### Why

Dispatch is the harness's core primitive. Without it, agents are still doing supervised work in a shared environment. Dispatch makes unsupervised operation safe by guaranteeing isolation — every agent works in its own worktree with its own database, and its output is a PR, not changes to a shared branch. Building dispatch before intake is deliberate: we need the execution engine running before we can test whether the intake agent's decompositions are actually dispatchable.

### Deliverables

`scripts/dispatch.sh` — the dispatch orchestrator. It performs, in order: validates that the issue exists and is labeled `ready-for-agent`; checks that the issue has no unresolved `blocked` label; creates a fresh git worktree from main; starts a Docker container with the dev environment mapped to the worktree; seeds the database from `tests/seeds/`; invokes Claude Code with the issue body as the task, the CLAUDE.md tree as context, and the worktree as the working directory; collects the resulting PR; links the PR to the issue; triggers the review pipeline (Phase 4); cleans up the worktree and container regardless of outcome.

`scripts/seed.ts` — database seeding script that produces deterministic test data. Uses faker with a fixed seed for reproducibility. Includes user records, role assignments, and sample data for any entities defined in the schema.

Per-issue environment isolation. Each dispatch creates: a git worktree at a unique path (`.worktrees/issue-<number>`), a Docker container named `dispatch-<issue-number>`, and a Postgres database named `dispatch_<issue_number>`. Cleanup is automatic — the dispatch script removes all three on exit, including on error.

Convention doc updates. The dispatch script's prompt instructs the implementation agent: when executing the first instance of a pattern in a directory, include a CLAUDE.md update in the PR that evolves the convention doc from prescriptive instructions to a pattern reference citing the new implementation.

Issue-level checkpointing. The dispatch script configures Claude Code to post progress updates as comments on the GitHub issue. The comments follow a structured format: status (in progress, blocked, completed, escalated), what was done, what remains, and any blockers encountered.

The CI budget mechanism. The dispatch script tracks how many CI cycles (push → CI run → fix) have occurred for a given dispatch. After N cycles (default: 5), it stops the agent, posts an escalation comment on the issue, and labels the issue `escalated`.

A GitHub Actions workflow `dispatch-on-label.yml` that triggers `/dispatch` when an issue is labeled `ready-for-agent`. This is the automation entry point — label an issue, and the pipeline takes over.

### Exit Criteria

`/dispatch <issue-number>` can be run from the command line and produces: an isolated worktree, a running dev environment in Docker, a seeded database, a PR linked to the issue, progress comments on the issue, and automatic cleanup. The GitHub Actions workflow triggers on label and runs the full dispatch pipeline. The CI budget mechanism correctly stops an agent after N failed rounds and posts an escalation comment. Two concurrent dispatches do not interfere with each other (tested by dispatching two issues simultaneously).

### First Tasks

1. Write `scripts/dispatch.sh` with the full orchestration flow.
2. Write `scripts/seed.ts` with deterministic seeding.
3. Implement worktree creation and cleanup logic.
4. Implement Docker container lifecycle (create, start, stop, remove) tied to dispatch.
5. Implement issue-level checkpointing (structured comments via GitHub CLI).
6. Implement CI budget tracking and escalation.
7. Write `dispatch-on-label.yml` GitHub Actions workflow.
8. Manually create a small test issue (e.g., "add a health-check API route at `/api/health`"), label it, and dispatch.
9. Test concurrent dispatch with two small issues.
10. Test CI budget: dispatch an issue designed to fail and verify escalation.

### Decisions

**Dispatch orchestrator: shell script or TypeScript?** Shell script (`dispatch.sh`). The dispatch orchestrator is a deterministic sequence of git, Docker, and GitHub CLI commands. Shell is the natural language for this. The agentic work happens inside the dispatched Claude Code session, not in the orchestrator. If the orchestrator grows complex enough to need structured error handling, it can be rewritten — but the charter principle is to contain the LLM in deterministic wrappers, and shell is the most deterministic wrapper available.

**Worktree location: inside or outside the repo?** Inside, at `.worktrees/`, which is gitignored. This keeps worktrees colocated with the repo for easy debugging while preventing them from appearing in git status.

**CI budget default: how many rounds?** Five. Stripe's Minions use two rounds as a hard ceiling, but their target is fixes in a mature codebase where the agent has extensive context. Our target is feature implementation in a growing codebase where agents may need more iteration. Five rounds is generous enough to allow self-correction but bounded enough to prevent infinite loops. Adjustable per-issue via a label (e.g., `ci-budget:3`).

**Cleanup on failure: automatic or manual?** Automatic. The dispatch script uses a trap to clean up on any exit, including errors and signals. Orphaned environments are a charter-level success criterion violation. If debugging is needed, the dispatch script has a `--keep` flag that skips cleanup — but the default is always clean up.

---

## Phase 4: Agent Review Pipeline

### Why

Agent-to-agent review is the charter's primary quality gate. Without it, the only review is human review, which defeats the unsupervised goal. The review pipeline makes agents accountable to each other, catches issues that linters and tests miss (logic errors, convention drift, unclear code), and produces a review record that helps human reviewers focus their time.

### Deliverables

The `/review` command implementation. When invoked on a PR, a review agent: reads the PR diff, reads the linked issue (the spec), reads the relevant CLAUDE.md files, and produces a structured review. The review covers: correctness (does the PR resolve the issue?), conventions (does the PR follow the CLAUDE.md rules?), tests (are they sufficient and meaningful?), types (are they precise, not `any`?), and accessibility (for UI changes, do they meet the charter's AA standard?).

Multi-pass review protocol. The implementation agent receives the review, addresses feedback, pushes updates, and requests re-review. This continues until the reviewer approves or the retry limit (default: 5 rounds) is reached. Each review round is posted as a PR comment with a structured format: approval status, issues found, issues resolved since last review, remaining concerns.

Escalation protocol. When the review cannot converge within the retry limit, the reviewer posts a summary comment listing all unresolved concerns and labels the PR `escalated`. The PR remains open for human review — it is not closed or abandoned.

Review assignment. By default, the reviewer is a separate Claude Code session invoked by the dispatch script. The reviewer has the same tools and context as the author but is a fresh session with no memory of the authoring process. This separation matters — the reviewer should evaluate the output, not rationalize the process.

Integration with the dispatch pipeline. The dispatch script (Phase 3) automatically triggers `/review` after the implementation agent produces a PR. The full loop is: dispatch → author produces PR → review → iterate → approve or escalate → human reviews.

### Exit Criteria

A dispatched issue that produces a PR is automatically reviewed by a separate agent session. The review catches at least one meaningful issue in a deliberately flawed test PR (a PR with a missing test, a vendor import outside a seam, or an accessibility violation). The multi-pass protocol correctly iterates: author fixes, reviewer re-reviews. Escalation fires correctly when the retry limit is reached. All review activity is visible as PR comments.

### First Tasks

1. Implement the `/review` command: PR diff reading, issue spec reading, CLAUDE.md reading, structured review output.
2. Implement the multi-pass protocol: review → author revision → re-review loop.
3. Implement escalation: retry limit tracking, escalation comment, label application.
4. Integrate `/review` into `scripts/dispatch.sh` as a post-authoring step.
5. Test with a clean PR: confirm review passes without issues.
6. Test with a deliberately flawed PR: confirm review catches the flaw.
7. Test escalation: submit a PR with an unfixable issue and confirm escalation fires after N rounds.

### Decisions

**Reviewer: same agent session or separate session?** Separate session. A fresh Claude Code invocation with no memory of the authoring process. This prevents the reviewer from rationalizing the author's decisions and produces a genuinely independent review. The cost is an additional API call; the benefit is review quality.

**Review scope: full PR or changed files only?** Changed files, plus any files they import from or are imported by (one level of transitive dependencies). Reviewing the entire codebase on every PR is wasteful. Reviewing only the diff misses broken integrations. One level of transitive dependency catches most integration issues without exploding the review scope.

**Review retry limit: how many rounds?** Five, matching the CI budget. A review that cannot converge in five rounds has a structural problem — the issue spec is ambiguous, the conventions are contradictory, or the change is too large. All of these are signals to escalate, not to iterate more.

---

## Phase 5: Intake and Triage

### Why

This phase builds the product-to-implementation bridge. Up to now, the harness can dispatch and review implementation-level issues — but someone has to write those issues by hand. The intake agent means a product person can write "users need to invite team members" and the system decomposes that into dispatchable implementation tasks. This is the phase that changes who the harness is for.

The convention-forward CLAUDE.md tree (built in Phase 2) is the intake agent's vocabulary. It reads the directory conventions to understand what patterns exist and how to specify implementation tasks at the right level of detail. The readiness tier validates that every issue is dispatch-ready before an agent picks it up.

### Deliverables

**The two-tier `/triage` command.**

Tier 1 — Intake. Triggered when the issue is labeled `product-brief` or when `/triage` detects the issue is written in product-level language (user outcomes, not file paths). The intake agent: reads the product brief, reads the codebase (schema, existing routes, existing seams), reads the CLAUDE.md convention docs for each relevant directory, and proposes a decomposition. The decomposition is posted as a structured comment on the brief issue listing each proposed child issue with: the directory conventions it follows, its key parameters, its dependencies on other child issues, and a one-line summary of what it produces. The comment ends with a request for human approval. On approval, the intake agent creates the child issues, links them to the parent brief, and labels dispatch-ready ones `ready-for-agent`.

Tier 2 — Readiness. Triggered when the issue is already implementation-level. The readiness tier evaluates whether the issue has enough detail for an implementation agent to execute without questions — checking it against the relevant directory's CLAUDE.md conventions. It either labels it `ready-for-agent`, flags missing inputs (with specific gaps listed), or proposes further breakdown.

Each implementation issue includes a "Definition of Done" section listing the mechanical checks: linter clean, tests pass, types check, accessibility audit clean (for UI), PR description links to issue.

### Exit Criteria

The intake agent, given a product-level brief, produces a decomposition that references the CLAUDE.md conventions for each relevant directory. The decomposition is posted as a comment and, on approval, child issues are created with correct labels and parent links. The readiness tier correctly classifies implementation issues and catches under-specified ones. At least one full intake → decomposition → approval → dispatch cycle has been tested end-to-end, producing a merged PR.

### First Tasks

1. Dry-run convention doc validation: feed each directory's CLAUDE.md to the intake agent with a synthetic brief and verify the decomposition references correct file paths, interfaces, and test expectations. Fix any gaps before building the full triage pipeline.
2. Implement `/triage` Tier 1 (intake): brief reading, codebase analysis, CLAUDE.md convention reading, decomposition proposal, comment posting.
3. Implement `/triage` Tier 2 (readiness): readiness evaluation against directory conventions, label application, gap identification.
4. Implement child issue creation from approved decompositions.
5. Test intake with a simple brief: "The app needs a health check endpoint that returns server status." Verify the intake agent proposes a well-specified issue and that dispatching it produces a working PR.
6. Test intake with a complex brief: "Users need to be able to create and manage projects." Verify the intake agent proposes multiple child issues (entity, pages, API routes) in the right dependency order, referencing the correct directory conventions.
7. Test readiness tier: submit an implementation issue missing required fields, verify it flags the gaps against the relevant CLAUDE.md.

### Decisions

**Intake auto-detection or explicit labeling?** Both. The intake agent runs when an issue is explicitly labeled `product-brief`, but `/triage` also auto-detects product-level language. Auto-detection uses a simple heuristic: if the issue body mentions user outcomes without specifying file paths or implementation details, it is treated as a product brief. The explicit label is the reliable path; auto-detection is a convenience.

**Decomposition approval: human-approved or automatic?** Human-approved. The intake agent proposes, the human confirms before child issues are created. Decomposition is a planning decision with scope implications — changing what gets built is a different kind of decision than how it gets built. Readiness classification and gap flagging are automatic because they are assessments, not decisions.

**What if a brief requires a pattern not covered by existing conventions?** The intake agent flags this in its decomposition comment: "No existing convention doc covers X. Proposed approach: [description]." After the issue is successfully dispatched and merged, the relevant directory's CLAUDE.md is updated to document the new pattern — so the next time the intake agent encounters a similar brief, the convention exists.

---

## Phase 6: Bootstrap the Product (via the Pipeline)

### Why

This is where the harness proves its core promise. Instead of building the product's auth, dashboard, and landing page through manual phases, we express them as product-level briefs and run them through the intake → dispatch → review pipeline. This validates the pipeline end-to-end, produces a running product, and creates a library of example issues that demonstrate how to feed the system.

### Deliverables

`scripts/bootstrap.sh` — the bootstrap orchestrator. It performs, in order: creates a new GitHub repository (or validates an existing one), initializes the GitHub Project board with required columns and labels, deploys harness infrastructure (CI, linters, hooks, CLAUDE.md tree) and stack scaffolding (Next.js, seam stubs, Docker) via Phases 1-2 artifacts, and then files the bootstrap brief catalog as issues labeled `product-brief`. From that point, the briefs flow through `/triage` → `/dispatch` → `/review` like any feature. The script is the deterministic wrapper around the creative bootstrap process.

The bootstrap brief catalog, filed as issues on the project:

**Brief 1: "The app needs user authentication — sign up, sign in, session management, and role-based access."** Expected decomposition: wire the auth seam (Clerk), add admin and member roles per `src/server/auth/CLAUDE.md`, create sign-in and sign-up pages per `src/app/CLAUDE.md`, wire Clerk webhook → DB sync.

**Brief 2: "There should be a dashboard behind auth where users land after signing in, with sidebar navigation, a user menu, and theme switching."** Expected decomposition: dashboard shell layout and index page per `src/app/CLAUDE.md`, sidebar and user menu components.

**Brief 3: "We need a public landing page that explains what the product does, with a clear call-to-action to sign up."** Expected decomposition: marketing landing page with SEO metadata per `src/app/CLAUDE.md`.

**Brief 4: "The app needs error tracking and performance monitoring so we can see what's breaking in production."** Expected decomposition: wire the observability seam (Sentry) per `src/server/CLAUDE.md`, add error boundary and source maps in CI.

**Brief 5: "We need product analytics — at minimum, tracking sign-ups, sign-ins, and page views."** Expected decomposition: wire the analytics seam (PostHog) per `src/server/CLAUDE.md`, add `user.signed_up`, `user.signed_in`, and `page.viewed` events per `src/server/analytics/CLAUDE.md`.

**Brief 6: "The app should support feature flags so we can roll out changes incrementally."** Expected decomposition: wire the flags seam (PostHog) per `src/server/CLAUDE.md`, add `show_welcome_banner` flag per `src/server/flags/CLAUDE.md` as proof-of-concept.

Each brief is filed, triaged by the intake agent, decomposition approved by the human, child issues dispatched, PRs reviewed and merged. The sequence matters — Brief 1 (auth) must complete before Brief 2 (dashboard behind auth) can dispatch. The intake agent should identify these dependencies in its decompositions.

### Exit Criteria

A user can visit the preview URL, see the marketing page, click sign up, create an account via Clerk, land on the dashboard, see their name in the user menu, toggle the theme, and sign out. All of this works — and all of it was built via the pipeline, not by hand. Sentry captures errors. PostHog receives events. Feature flags resolve. The database contains the user record synced via webhook. CI is green. Every brief issue has its decomposition comment, approved child issues, and linked merged PRs visible on the Project board.

The bootstrap briefs and their decompositions serve as reference examples. A new user reading Brief 1 can see: the product-level description, the intake agent's decomposition, the approved child issues, and the merged PRs — the full lifecycle.

### First Tasks

1. Write `scripts/bootstrap.sh` — the bootstrap orchestrator that creates the repo, deploys infrastructure, and files briefs.
2. Write the bootstrap brief catalog in `harness/bootstrap-briefs/`.
3. File Brief 1 (auth) as a GitHub Issue labeled `product-brief`.
4. Run `/triage` on Brief 1. Review the intake agent's decomposition. Adjust if needed. Approve.
5. Let `dispatch-on-label` pick up the child issues. Monitor. Review PRs.
6. Once Brief 1's PRs are merged, file Brief 2 (dashboard). Repeat the cycle.
7. Continue through Briefs 3-6, filing each when its dependencies are met.
8. After all briefs are resolved: full validation — sign-up flow, dashboard, theme toggle, analytics, flags, error tracking.
9. Review the full trail of issues, decompositions, and PRs. Note what the intake agent got right and wrong. Note where implementation agents struggled. These observations feed Phase 8 (retrospective).

### Decisions

**Brief ordering: sequential or parallel?** Sequential by dependency. Brief 1 (auth) must complete before Brief 2 (dashboard behind auth). Briefs 3 (landing page), 4 (observability), 5 (analytics), and 6 (flags) can be parallelized after Brief 1 completes, since they have no dependency on each other. The intake agent should identify these dependencies; the human confirms.

**What if a brief requires a pattern not covered by existing conventions?** The intake agent flags this in its decomposition. If the pattern is novel, the human can approve a custom issue. After the issue is successfully dispatched and merged, the relevant directory's CLAUDE.md is updated to document the new pattern — conventions grow through use.

**How much human intervention is allowed during bootstrap?** Minimal. The human approves intake decompositions and reviews merged PRs. They do not write code, do not modify agent output, and do not add manual commits to agent branches. If an agent escalates, the human can revise the issue spec and re-dispatch — but they do not fix the code themselves. This discipline is what makes bootstrap a valid test of the pipeline.

---

## Phase 7: GC Sweepers and Quality Automation

### Why

Unsupervised agents produce entropy. Even with strong conventions, dead code accumulates, documentation drifts, dependencies go stale, and test coverage develops gaps. The GC sweepers are the harness's immune system — they detect degradation and either fix it automatically or flag it for attention.

### Deliverables

`docs/quality-score.md` — auto-generated dashboard tracking: test coverage (line and branch), type coverage (percentage of `any` types), accessibility compliance (axe-core violation count across e2e tests), bundle size (total and per-route), dependency freshness (count of outdated dependencies), and documentation staleness (files in `docs/` not updated in 30+ days).

`docs/generated/harness-metrics.md` — auto-generated harness health metrics: dispatch success rate, average CI rounds per dispatch, escalation rate, review convergence rate, intake decomposition accuracy, convention pattern frequency, and average time from dispatch to merged PR.

A GC sweeper script that runs on a schedule (weekly via GitHub Actions) or on demand. It: identifies dead exports (exported but never imported), identifies unused dependencies, checks for `any` types in production code, verifies that every seam's linter rule is active, verifies that every user-facing route has a Playwright test, and generates `docs/quality-score.md`.

A doc-gardener script that: checks CLAUDE.md files against the actual directory structure (flagging references to moved or deleted files), checks ADRs for superseded decisions, and flags documentation that references packages or APIs that no longer exist in `package.json`.

Renovate configured with: auto-merge for patch-level dependency updates that pass CI, grouped PRs for minor-level updates, manual review required for major-level updates, and a weekly merge schedule to avoid update fatigue.

### Exit Criteria

`docs/quality-score.md` is generated and accurate. `docs/generated/harness-metrics.md` is generated with real data from Phase 6's bootstrap dispatches. The GC sweeper runs without errors and correctly identifies at least one piece of dead code or stale documentation. Renovate is configured and producing dependency update PRs. The weekly GitHub Actions workflow for the GC sweeper runs successfully.

### First Tasks

1. Write the quality-score generation script.
2. Write the harness-metrics generation script. Populate with data from Phase 6 dispatches.
3. Write the GC sweeper: dead exports, unused deps, `any` types, seam linter verification, route test coverage.
4. Write the doc-gardener: CLAUDE.md consistency, ADR staleness, stale doc references.
5. Configure Renovate with the specified merge policy.
6. Write the GitHub Actions workflow for weekly GC sweep.
7. Run the full sweep against the post-bootstrap codebase and verify output.

### Decisions

**GC sweeper output: PRs or reports?** Both. The sweeper generates `docs/quality-score.md` as a report and, for mechanical fixes (removing unused imports, deleting dead exports), produces auto-refactor PRs. PRs go through the same review pipeline as agent-authored PRs. This keeps the quality loop closed — degradation is detected, fixed, reviewed, and merged without human initiation.

**Sweep frequency: per-PR, daily, or weekly?** Weekly for the full sweep. Per-PR for a lightweight subset (bundle size delta, new `any` types, new accessibility violations) that runs as part of CI. Daily is too noisy; per-PR for the full sweep is too slow.

---

## Phase 8: Dogfood — Build the Real Product

### Why

The bootstrap in Phase 6 proved the pipeline works for foundational features. Now we use it to build the actual product — whatever this project is for. This is where the harness encounters real product complexity: features that span multiple concerns, briefs that require creative decomposition, edge cases that existing conventions don't cover. Dogfooding at scale reveals what the harness still lacks.

### Deliverables

A set of product features built entirely via the pipeline. The product itself is defined by the person using the harness — the harness is agnostic to what gets built. What matters is that the build exercises the full loop at scale: at least five product-level briefs triaged through intake, at least ten implementation issues dispatched, at least three different convention patterns exercised, at least two escalations that required human intervention.

A retrospective document in `docs/decisions/` recording: what the intake agent got right and wrong, which convention patterns were most and least reliable, where implementation agents struggled, which conventions need tightening, and what new patterns should be documented. This document drives the next iteration of the charter, plan, and convention docs.

Updates to the charter, plan, and CLAUDE.md convention docs based on dogfood findings.

### Exit Criteria

At least five product-level briefs have been processed through the full pipeline. The dispatch success rate, CI round average, escalation rate, and intake decomposition accuracy are measured and recorded in `docs/generated/harness-metrics.md`. The retrospective document exists and identifies at least three concrete improvements. Those improvements are filed as issues.

### First Tasks

1. Write the first batch of product-level briefs for the features you want.
2. File them, triage them, approve decompositions, and let the pipeline run.
3. Monitor dispatch and review cycles. Note friction points.
4. After ten+ dispatched issues, review the harness metrics.
5. Write the retrospective.
6. File improvement issues based on the retrospective.
7. Update conventions and CLAUDE.md files based on findings.

### Decisions

**Dogfood product: real or synthetic?** Real. A synthetic product does not create the pressure that reveals harness weaknesses. Build something you actually want to ship. The stakes must be real for the feedback to be real.

**When to stop dogfooding and call it v1.0?** After five product-level briefs have been fully processed (intake → dispatch → review → merge), with the retrospective written and improvement issues filed. The threshold is not "the harness is perfect" — it is "the harness has proven the loop works end-to-end and we know what to improve next."

---

## Global Decisions

These decisions apply across all phases. They are recorded here rather than in a single phase because they affect the entire plan.

**Agent runtime: Claude Code.** The harness is built on Claude Code, invoked via CLI. The dispatch system calls Claude Code with structured prompts derived from issue bodies. Claude Code's hook system, MCP integration, and CLAUDE.md conventions are foundational to the harness. This is not a pluggable decision — swapping agent runtimes would require redesigning the harness.

**Version control branching model: trunk-based with short-lived feature branches.** Every dispatch creates a branch named `issue-<number>/<short-description>`. Branches are merged via PR to `main`. There are no long-lived release branches, no develop branch, no gitflow. The harness targets continuous delivery — every merge to main is deployable.

**Environment variables: `.env.example` checked in, `.env` gitignored.** Environment variable schemas are enforced by `@t3-oss/env-nextjs`. The `.env.example` file documents every variable with a description and example value. Actual secrets are set in Vercel environment settings and in GitHub Actions secrets.

**Documentation format: Markdown in `docs/`, ADRs in `docs/decisions/`.** No external documentation systems. No wikis. No Notion. Everything an agent needs is in the repository. This is a charter principle — from the agent's point of view, what it can't access in-context effectively does not exist.

**Error handling pattern: Result types for expected errors, thrown exceptions for unexpected errors.** Expected errors (validation failures, not-found, permission denied) return typed Result objects. Unexpected errors (database connection failures, unhandled edge cases) throw and are caught by Sentry via the error boundary. This pattern is documented in the root CLAUDE.md and enforced by code review.

**API route pattern: Route Handlers with Zod validation.** Every API route validates its input with Zod before processing. Invalid input returns a 400 with a structured error response. This pattern is specified in `src/server/db/CLAUDE.md` and `src/app/CLAUDE.md` so agents implement it consistently.

---

## Done Criteria for v1.0

The harness is v1.0 when all of the following are true:

A product person can write a product-level brief, file it as an issue, and the intake agent produces a correct decomposition into implementation issues without human revision at least 90% of the time.

The dispatch system works end-to-end: implementation issues are picked up in isolation, produce PRs, reviewed by a separate agent, and the PRs are ready for human merge. Dispatch success rate exceeds 80% (escalation rate under 20%).

Bootstrap via the pipeline produces a running, deployed Next.js application with all day-one vendor seams live, auth working end-to-end, and a preview URL accessible — all built through briefs, not manual phases.

The CLAUDE.md convention docs cover all seven standard patterns specified in the charter (entity, role, page, vendor seam, seam wiring, analytics event, feature flag), each validated via at least one successful dispatch.

The CLAUDE.md tree is complete: every significant directory has a scoped CLAUDE.md, the root CLAUDE.md serves as an accurate table of contents, and a freshly dispatched agent can orient itself without external context.

CI gates all PRs with: type-check, lint (including seam linters), unit tests, integration tests, e2e tests with accessibility audits, bundle analysis, and secret scanning. A PR with any violation cannot merge.

The quality score and harness metrics are generated and accurate, with real data from at least the bootstrap dispatches.

At least one real product has been dogfooded through the harness from product briefs to merged features, and the retrospective has been written.

Bootstrap to first merged feature PR in under 4 hours of wall-clock time, with no human intervention between brief approval and PR review.

Agent-to-agent review converges within 3 review-revise cycles at least 90% of the time. Reviews that exceed 3 passes indicate underspecified issue specs or conventions.

No orphaned environments. Every dispatched worktree and Docker container is cleaned up after the dispatch completes, whether successfully or via escalation.

The quality score in `docs/quality-score.md` shows stable or improving trends in test coverage, type coverage, accessibility compliance, bundle size, and dependency freshness. A sustained downward trend in any metric triggers a GC sweep.

---

*This plan is a companion to the charter, not a replacement. The charter says what must be true. This plan says how to make it true. When they disagree, update the plan.*
