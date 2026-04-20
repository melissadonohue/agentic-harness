# eslint-rules/ — Custom Linter Rule Conventions

This directory contains custom ESLint rules that mechanically enforce the harness's architectural invariants. These are sensors — they observe agent output and prevent violations before code reaches CI.

## Purpose

The primary use case is vendor seam containment. Each vendor seam gets a custom rule that errors on vendor SDK imports outside the seam module. These rules are the mechanical enforcement layer described in the charter — markdown warns of nothing, linters gate.

## Rule File Convention

One file per rule. File naming: `no-<vendor>-outside-<seam>.js`.

Example: `no-vendor-outside-seam.js` is the reference implementation that handles all day-one seams via configuration.

### Rule Structure

Every custom rule must:

1. Export a valid ESLint rule object with `meta` and `create`.
2. Include a `meta.messages` entry with a remediation hint — the error message tells the agent what is wrong and how to fix it.
3. Target `ImportDeclaration` and `CallExpression` (for `require()`) AST nodes.
4. Be configurable via the rule's options or the ESLint config to specify which packages map to which seam directories.

### Error Messages as Remediation Hints

Error messages are not opaque failures — they are instructions to the agent. Every message must:

- Name the banned import.
- Name the seam directory where the import belongs.
- Suggest the correct import path.

Example: `"Import '@clerk/nextjs' is only allowed inside 'src/server/auth/'. Use the auth seam's exported interface instead: import { ... } from '@/server/auth'."`

## Day-One Seam Mappings

| Vendor Package               | Seam Directory              | Seam Import              |
| ---------------------------- | --------------------------- | ------------------------ |
| `@clerk/nextjs`              | `src/server/auth/`          | `@/server/auth`          |
| `posthog-js`, `posthog-node` | `src/server/analytics/`     | `@/server/analytics`     |
| `@sentry/nextjs`             | `src/server/observability/` | `@/server/observability` |
| `posthog-js` (flags)         | `src/server/flags/`         | `@/server/flags`         |
| `drizzle-orm`, `drizzle-kit` | `src/server/db/`            | `@/server/db`            |

Note: PostHog is used for both analytics and feature flags. The rule configuration must allow PostHog imports in both `src/server/analytics/` and `src/server/flags/`.

## Adding a New Seam Rule

When a new vendor seam is introduced (via a product brief → intake → dispatch cycle):

1. Add the vendor package and seam directory mapping to the rule configuration in `.eslintrc.cjs`.
2. The reference rule (`no-vendor-outside-seam.js`) handles the enforcement — no new rule file is needed unless the seam has unusual containment requirements.
3. Update this CLAUDE.md to include the new mapping in the table above.
