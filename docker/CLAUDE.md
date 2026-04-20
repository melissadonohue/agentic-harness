# docker/ — Docker and Dev Environment

This directory contains the Docker configuration for the fully local, fully reproducible development environment. No shared staging databases, no remote services required for local development.

## Files

- `docker-compose.yml` — Defines the local dev services: Postgres and Mailpit.
- `Dockerfile.dev` — Dev container used by `scripts/dispatch.sh` for isolated dispatch environments.

## Services

### Postgres

- **Image**: `postgres:17-alpine`
- **Port**: `5432`
- **Credentials**: user `harness`, password `harness`, database `harness_dev` (matches `.env.example`).
- **Data persistence**: Named volume `pgdata`. Data survives container restarts but is removed with `down -v`.
- **Health check**: `pg_isready` runs every 5 seconds.

### Mailpit

- **Image**: `axllent/mailpit:latest`
- **Web UI**: `http://localhost:8025` — View captured emails in the browser.
- **SMTP**: `localhost:1025` — Point application email sending here in development.
- **Auth**: Accepts any credentials (dev-only configuration).

## Commands

### Start Services

```bash
docker compose -f docker/docker-compose.yml up -d
```

### Stop Services

```bash
docker compose -f docker/docker-compose.yml down
```

### Reset All Data (Removes Volumes)

```bash
docker compose -f docker/docker-compose.yml down -v
```

This removes the Postgres data volume, wiping all database data. Use when you need a clean slate.

### View Logs

```bash
docker compose -f docker/docker-compose.yml logs -f postgres
docker compose -f docker/docker-compose.yml logs -f mailpit
```

## Mailpit as Agent Sensor

Mailpit captures all outgoing emails sent via SMTP on port 1025. Agents use Mailpit's REST API to verify email delivery and content in tests and during development.

### API Endpoints

**List all messages**:

```
GET http://localhost:8025/api/v1/messages
```

**Search by recipient**:

```
GET http://localhost:8025/api/v1/search?query=to:user@example.com
```

**Get a specific message** (by ID from the list response):

```
GET http://localhost:8025/api/v1/message/{id}
```

**Delete all messages** (clean up between test runs):

```
DELETE http://localhost:8025/api/v1/messages
```

### Using Mailpit in Tests

```typescript
// In an integration or e2e test
const response = await fetch('http://localhost:8025/api/v1/messages');
const data = await response.json();

expect(data.messages).toHaveLength(1);
expect(data.messages[0].Subject).toBe('You have been invited');
```

### Using Mailpit in Development

When developing email features, configure the application's email seam to use `localhost:1025` as the SMTP host. Open `http://localhost:8025` in a browser to view captured emails in real time.

## Dispatch Isolation

The `Dockerfile.dev` defines the dev container image used by `scripts/dispatch.sh` for isolated dispatch environments. Each dispatch creates:

- A Docker container named `dispatch-<issue-number>`.
- A Postgres database named `dispatch_<issue_number>`, seeded from `tests/seeds/`.
- A git worktree at `.worktrees/issue-<number>`.

All three are cleaned up automatically when the dispatch completes (success or failure). The cleanup trap in `dispatch.sh` ensures no orphaned environments.

## Database Connection

The default connection URL for local development:

```
DATABASE_URL=postgresql://harness:harness@localhost:5432/harness_dev
```

This matches the `.env.example` file. Do not commit actual `.env` files to the repository.

## Rules

- Dev environment is fully local — no shared staging databases, no remote services.
- Docker volumes persist Postgres data between restarts. Use `down -v` to reset.
- Mailpit does not require authentication in dev mode.
- Never commit credentials beyond the documented dev defaults (`harness` / `harness`).
