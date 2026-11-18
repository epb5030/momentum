# momentum — Project Planning (0.1 Draft)

**Code name:** `momentum`
**Display name:** **Project Momentum**
**Vision:** AI-first cast tracking to-do application. Open source, self-hosted, CLI-first, API-heavy for agent interaction. No paid-gated features.

---

## 1. Core Philosophy

| Principle | Detail |
|-----------|--------|
| **AI-first** | Every feature designed for agent consumption; UI is secondary |
| **CLI-native** | Full CLI parity with API; `momentum` command does everything |
| **API-heavy** | REST + GraphQL + WebSocket; agents drive workload |
| **Open core** | 100% MIT/Apache-2.0; no paid plugins, no enterprise fork |
| **Self-hosted first** | Single binary, Docker, runs on Unraid/homelab |
| **Event-sourced** | Full audit trail, replay, AI reasoning over history |
| **Plugin architecture** | Core minimal; features as plugins (UI, integrations, fields) |
| **Data ownership** | Local-first, export/import, no vendor lock-in |

---

## 2. Target Users & Use Cases

| Persona | Needs |
|---------|-------|
| **Solo developer** | Personal task management, AI daily planning, git integration |
| **Small team** | Shared projects, assignments, comments, retrospectives |
| **AI agent / automation** | Programmatic task CRUD, planning, prioritization, webhooks |
| **Power user** | Keyboard-driven, vim-like, scriptable, keyboard shortcuts |

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Clients                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────────────┐ │
│  │   CLI   │  │   Web   │  │  Agent  │  │  3rd Party     │ │
│  │ (cobra) │  │ (HTMX/  │  │ (REST/  │  │  (webhooks,    │ │
│  │         │  │  React) │  │  GraphQL)│  │   integrations)│ │
│  └────┬────┘  └────┬────┘  └────┬────┘  └───────┬────────┘ │
└───────┼────────────┼────────────┼──────────────┼──────────┘
        │            │            │              │
        └────────────┴─────┬──────┴──────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      API Gateway (Go)                       │
│  REST + GraphQL + WebSocket + gRPC                          │
└─────────────────────────┬───────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Core Domain  │  │  Plugin Host  │  │  AI Services  │
│  (tasks,      │  │  (WASM/       │  │  (embeddings, │
│   projects,   │  │   native)     │  │   planning,   │
│   users)      │  │               │  │   prioritize) │
└───────┬───────┘  └───────┬───────┘  └───────┬───────┘
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ▼
        ┌─────────────────────────────────────┐
        │       PostgreSQL + pgvector         │
        │  (events, tasks, embeddings, users) │
        └─────────────────────────────────────┘
```

---

## 4. Data Models (PostgreSQL + pgvector)

### Core Tables

```sql
-- Users & Auth
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT UNIQUE NOT NULL,
    name            TEXT,
    avatar_url      TEXT,
    password_hash   TEXT,
    oidc_sub        TEXT UNIQUE,
    settings        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE api_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    key_hash        TEXT NOT NULL,
    scopes          TEXT[] DEFAULT '{}',
    last_used_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Workspaces & Projects
CREATE TABLE workspaces (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    owner_id        UUID REFERENCES users(id),
    settings        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE workspace_members (
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT DEFAULT 'member',
    joined_at       TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (workspace_id, user_id)
);

CREATE TABLE projects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    description     TEXT,
    color           TEXT DEFAULT '#6366f1',
    icon            TEXT,
    archived_at     TIMESTAMPTZ,
    settings        JSONB DEFAULT '{}',
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Tasks (core entity)
CREATE TABLE tasks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID REFERENCES projects(id) ON DELETE CASCADE,
    parent_id       UUID REFERENCES tasks(id) ON DELETE SET NULL,
    title           TEXT NOT NULL,
    description_md  TEXT,
    status          TEXT NOT NULL DEFAULT 'todo',
    priority        INTEGER DEFAULT 0,
    assignee_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    reporter_id     UUID REFERENCES users(id),
    due_at          TIMESTAMPTZ,
    start_at        TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    position        INTEGER DEFAULT 0,
    recurrence_rule TEXT,
    recurrence_parent_id UUID REFERENCES tasks(id),
    metadata        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    deleted_at      TIMESTAMPTZ
);

-- Task dependencies
CREATE TABLE task_dependencies (
    task_id         UUID REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_id   UUID REFERENCES tasks(id) ON DELETE CASCADE,
    type            TEXT DEFAULT 'blocks',
    created_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (task_id, depends_on_id)
);

-- Tags
CREATE TABLE tags (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    color           TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE (workspace_id, name)
);

CREATE TABLE task_tags (
    task_id         UUID REFERENCES tasks(id) ON DELETE CASCADE,
    tag_id          UUID REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, tag_id)
);

-- Comments
CREATE TABLE comments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id         UUID REFERENCES tasks(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    content_md      TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

-- Attachments
CREATE TABLE attachments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id         UUID REFERENCES tasks(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id),
    filename        TEXT NOT NULL,
    mime_type       TEXT,
    size_bytes      BIGINT,
    storage_path    TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Event sourcing
CREATE TABLE events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  TEXT NOT NULL,
    aggregate_id    UUID NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    user_id         UUID REFERENCES users(id),
    ip              INET,
    user_agent      TEXT,
    request_id      UUID,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_events_aggregate ON events (aggregate_type, aggregate_id, created_at);

-- AI: Task embeddings
CREATE TABLE task_embeddings (
    task_id         UUID PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
    embedding       vector(1536) NOT NULL,
    model           TEXT NOT NULL DEFAULT 'text-embedding-3-small',
    content_hash    TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- AI: Agent sessions
CREATE TABLE agent_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    agent_type      TEXT NOT NULL,
    context         JSONB DEFAULT '{}',
    started_at      TIMESTAMPTZ DEFAULT now(),
    ended_at        TIMESTAMPTZ
);

-- Webhooks
CREATE TABLE webhooks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    url             TEXT NOT NULL,
    secret          TEXT NOT NULL,
    events          TEXT[] NOT NULL,
    active          BOOLEAN DEFAULT true,
    last_triggered  TIMESTAMPTZ,
    failure_count   INTEGER DEFAULT 0,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Plugin system
CREATE TABLE plugins (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT UNIQUE NOT NULL,
    version         TEXT NOT NULL,
    description     TEXT,
    author          TEXT,
    repository_url  TEXT,
    manifest        JSONB NOT NULL,
    wasm_bytes      BYTEA,
    enabled         BOOLEAN DEFAULT false,
    installed_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE plugin_configs (
    plugin_id       UUID REFERENCES plugins(id) ON DELETE CASCADE,
    workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    config          JSONB DEFAULT '{}',
    enabled         BOOLEAN DEFAULT true,
    PRIMARY KEY (plugin_id, workspace_id)
);
```

---

## 5. API Design (REST + GraphQL + WebSocket)

### REST Endpoints

```yaml
/api/v1:
  /auth:
    POST   /login
    POST   /logout
    POST   /refresh
    POST   /register
    GET    /me

  /workspaces:
    GET    /
    POST   /
    GET    /{id}
    PATCH  /{id}
    DELETE /{id}
    GET    /{id}/members
    POST   /{id}/members
    PATCH  /{id}/members/{userId}
    DELETE /{id}/members/{userId}

  /projects:
    GET    /
    POST   /
    GET    /{id}
    PATCH  /{id}
    DELETE /{id}
    GET    /{id}/tasks
    GET    /{id}/stats

  /tasks:
    GET    /
    POST   /
    GET    /{id}
    PATCH  /{id}
    DELETE /{id}
    POST   /{id}/subtasks
    GET    /{id}/subtasks
    POST   /{id}/dependencies
    GET    /{id}/dependencies
    DELETE /{id}/dependencies/{depId}
    POST   /{id}/comments
    GET    /{id}/comments
    POST   /{id}/tags
    DELETE /{id}/tags/{tagId}
    GET    /{id}/events
    POST   /{id}/attachments
    GET    /{id}/attachments

  /search:
    POST   /tasks
    GET    /suggestions

  /ai:
    POST   /chat
    POST   /plan
    POST   /prioritize
    POST   /summarize
    POST   /embed
    POST   /categorize

  /webhooks:
    GET    /
    POST   /
    GET    /{id}
    PATCH  /{id}
    DELETE /{id}
    POST   /{id}/test

  /plugins:
    GET    /
    POST   /install
    PATCH  /{id}
    DELETE /{id}
    GET    /{id}/config
    PATCH  /{id}/config
```

### GraphQL Schema

```graphql
type Task {
  id: ID!
  project: Project!
  parent: Task
  subtasks: [Task!]!
  title: String!
  description: String
  status: TaskStatus!
  priority: Int!
  assignee: User
  reporter: User!
  dueAt: DateTime
  startAt: DateTime
  completedAt: DateTime
  position: Int!
  tags: [Tag!]!
  dependencies: [TaskDependency!]!
  comments: [Comment!]!
  attachments: [Attachment!]!
  metadata: JSON!
  createdAt: DateTime!
  updatedAt: DateTime!
}

type Query {
  task(id: ID!): Task
  tasks(filter: TaskFilter, pagination: Pagination): TaskConnection!
  project(id: ID!): Project
  projects(filter: ProjectFilter): [Project!]!
  searchTasks(query: String!, filter: TaskFilter): [Task!]!
  aiChat(sessionId: ID, message: String!): AIChatResponse!
}

input TaskFilter {
  projectId: ID
  assigneeId: ID
  status: [TaskStatus!]
  tags: [ID!]
  dueBefore: DateTime
  dueAfter: DateTime
  priorityMin: Int
  priorityMax: Int
  hasSubtasks: Boolean
  isRecurring: Boolean
}
```

---

## 6. Tech Stack Decisions

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **Language** | **Go 1.23+** | Single binary, great concurrency, stdlib HTTP, easy cross-compile |
| **API Framework** | `chi` + `gqlgen` | Lightweight, stdlib-compatible, GraphQL codegen |
| **Database** | **PostgreSQL 16+** + `pgvector` | ACID, JSONB, vectors, mature, your existing infra |
| **ORM** | `sqlc` + `goose` | Type-safe SQL, migrations, no runtime overhead |
| **Auth** | **OIDC** (Authentik) + JWT | Your existing SSO, standard, delegated |
| **Queue** | **Redis** + `asynq` | Reliable, priority queues, retries, your infra |
| **Realtime** | **NATS** or Redis Pub/Sub | WebSocket push, horizontal scale |
| **CLI** | `cobra` + `bubbletea` | Rich TUI, autocomplete, keybindings |
| **Web UI** | **HTMX + Alpine.js** (optional) | Server-rendered, minimal JS, fast |
| **Container** | `Dockerfile` (multi-stage) | Single binary, ~20MB, runs anywhere |
| **Observability** | `otel` + Prometheus/Grafana | Your existing stack |
| **Testing** | `testify` + `ginkgo` | Unit, integration, contract tests |

---

## 7. Authentication & Multi-tenancy

### Auth Flow (OIDC via Authentik)

```
Client → API Gateway → Authentik (OIDC) → JWT (RS256)
```

### JWT Claims

```json
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "workspaces": [{"id": "ws-uuid", "role": "owner"}],
  "scopes": ["tasks:read", "tasks:write", "ai:chat"],
  "iat": 1234567890,
  "exp": 1234571490
}
```

### Multi-tenancy

- **Workspace** = top-level tenant boundary
- **Projects** belong to workspace
- **Users** belong to workspace(s) with roles
- **Tasks** belong to project → workspace
- **RLS policies** enforce isolation at DB level

---

## 8. Plugin Architecture

### Plugin Manifest (`plugin.json`)

```json
{
  "name": "github-integration",
  "version": "1.0.0",
  "description": "Sync tasks with GitHub issues",
  "author": "community",
  "repository": "https://github.com/momentum/plugins/github",
  "permissions": ["tasks:read", "tasks:write", "webhooks:read", "webhooks:write"],
  "hooks": ["task.created", "task.updated", "task.completed"],
  "config_schema": {
    "type": "object",
    "properties": {
      "github_token": {"type": "string", "format": "password"},
      "repo": {"type": "string", "pattern": "^.+/.+$"},
      "sync_labels": {"type": "boolean", "default": true}
    },
    "required": ["github_token", "repo"]
  }
}
```

### Plugin Runtime

- **WASM** (preferred) — sandboxed, language-agnostic, fast startup
- **Native (Go plugins)** — for performance-critical paths
- **External (HTTP)** — for long-running, language-agnostic

### Hook Points

| Hook | Payload | Sync/Async |
|------|---------|------------|
| `task.created` | Task | Async |
| `task.updated` | Task, diff | Async |
| `task.deleted` | Task ID | Async |
| `task.status_changed` | Task, old_status, new_status | Async |
| `task.assigned` | Task, user | Async |
| `comment.created` | Comment | Async |
| `ai.plan_requested` | Goal, context | Sync |
| `ai.prioritize_requested` | Task[] | Sync |

---

## 9. AI Integration Points

### 1. Natural Language → Task (Planning)

```go
// POST /api/v1/ai/plan
// Input: "Plan a blog post about Rust vs Go for web services by Friday"
// Output: Task tree with subtasks, estimates, dependencies
```

### 2. Smart Prioritization

```go
// POST /api/v1/ai/prioritize
// Input: [Task IDs] or project ID
// Output: Ranked list with scores (deadline, deps, history, estimates)
```

### 3. Daily Planning

```go
// GET /api/v1/ai/daily-plan?date=2026-01-15
// Output: Ranked tasks for today with time blocks
```

### 4. Semantic Search

```go
// POST /api/v1/search/tasks
// Input: "swimwear size 34 jammer"
// Vector search over task_embeddings + full-text
```

### 5. Summarization

```go
// POST /api/v1/ai/summarize
// Input: period (week, month), project/workspace
// Output: Accomplishments, patterns, suggestions
```

### 6. Agent Chat (Streaming SSE)

```go
// POST /api/v1/ai/chat (SSE)
// Context: current tasks, recent activity, user preferences
```

### Embedding Pipeline

```go
func EmbedTask(task *Task) {
    content := task.Title + "\n" + task.Description
    hash := sha256(content)
    if existing, _ := db.GetEmbedding(task.ID); existing.Hash == hash {
        return
    }
    vec := openai.Embed(content, "text-embedding-3-small")
    db.UpsertEmbedding(task.ID, vec, hash, model)
}
```

---

## 10. MVP Scope (0.1)

### Must Have

- [ ] User auth (OIDC + local fallback)
- [ ] Workspaces & projects CRUD
- [ ] Tasks: CRUD, list, filter
- [ ] Task hierarchy (parent/subtask)
- [ ] Task dependencies (blocks/relates)
- [ ] Tags & assignment
- [ ] Due dates, priority, status
- [ ] REST API + OpenAPI spec
- [ ] GraphQL endpoint
- [ ] CLI (`momentum task create`, `list`, `update`, `done`)
- [ ] JWT auth + API keys
- [ ] Event sourcing (all mutations)
- [ ] PostgreSQL + pgvector setup
- [ ] Docker image + docker-compose
- [ ] Basic web UI (HTMX) — task list, create, edit

### Nice to Have (0.2+)

- [ ] Recurring tasks (RRULE)
- [ ] Comments & attachments
- [ ] Webhooks
- [ ] AI planning endpoint
- [ ] AI prioritization
- [ ] Semantic search (pgvector)
- [ ] Plugin system (WASM)
- [ ] Rich TUI (bubbletea)
- [ ] Webhooks
- [ ] Notifications
- [ ] Time tracking
- [ ] Custom fields
- [ ] Export/import (JSON, CSV, markdown)
- [ ] Mobile PWA

---

## 11. Deployment Strategy

### Docker Compose (Development)

```yaml
services:
  api:
    build: .
    ports: ["8080:8080"]
    environment:
      - DATABASE_URL=postgres://postgres:pass@db:5432/momentum
      - REDIS_URL=redis://redis:6379
      - OIDC_ISSUER=https://auth.yorkshire.casa
      - OIDC_CLIENT_ID=momentum
      - OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
      - JWT_SECRET=${JWT_SECRET}
    depends_on: [db, redis]

  db:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_DB=momentum
      - POSTGRES_PASSWORD=pass
    volumes: ["pgdata:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine

  nats:
    image: nats:latest
```

### Production (Unraid)

- Single binary in `/mnt/user/appdata/momentum/`
- systemd service or Docker container
- PostgreSQL on existing `postgresql18` container
- Redis on existing Redis container
- Nginx Proxy Manager for HTTPS + custom domain
- Tailscale serve for tailnet access
- Backups via existing pg_dump cron

---

## 12. Development Workflow

```bash
# Setup
make dev-setup          # install tools, generate code
make migrate            # run migrations
make dev                # run API + watch

# CLI development
make cli-build          # builds momentum binary
momentum task create "test" --project personal

# Testing
make test               # unit tests
make test-integration   # integration tests (needs db/redis)
make test-contract      # OpenAPI contract tests

# Release
goreleaser release --clean
```

### Project Structure

```
momentum/
├── cmd/
│   ├── api/           # API server entrypoint
│   ├── cli/           # CLI entrypoint (cobra)
│   └── migrate/       # Migration runner
├── internal/
│   ├── api/           # HTTP handlers, middleware
│   ├── auth/          # OIDC, JWT, API keys
│   ├── domain/        # Core business logic
│   │   ├── task/      # Task aggregate
│   │   ├── project/   # Project aggregate
│   │   ├── user/      # User aggregate
│   │   └── workspace/ # Workspace aggregate
│   ├── ai/            # AI services
│   ├── db/            # sqlc-generated + custom queries
│   ├── events/        # Event store
│   ├── plugins/       # Plugin host
│   ├── queue/         # asynq jobs
│   └── search/        # Full-text + vector
├── pkg/
│   ├── errors/        # Error types
│   └── validation/    # Validators
├── web/               # HTMX templates, static assets
├── migrations/        # Goose SQL migrations
├── api/
│   ├── openapi.yaml
│   └── graphql/
├── docker/
├── Makefile
├── go.mod
├── go.sum
├── Dockerfile
├── docker-compose.yml
├── .goreleaser.yaml
└── README.md
```

---

## 13. Roadmap Beyond 0.1

| Version | Focus |
|---------|-------|
| **0.1** | Core CRUD, API, CLI, Auth, Events, Docker |
| **0.2** | AI Planning, Prioritization, Semantic Search, Webhooks |
| **0.3** | Plugin System (WASM), Recurring Tasks, Comments, Attachments |
| **0.4** | Rich TUI, Time Tracking, Custom Fields, Export/Import |
| **0.5** | Multi-user Collaboration, Real-time, Notifications |
| **1.0** | Plugin Marketplace, Mobile PWA, Self-hosted Analytics |

---

## 14. Open Questions for 0.1 Draft — Decisions

| # | Question | Decision for 0.1 | Notes |
|---|----------|------------------|-------|
| 1 | **Web UI in MVP?** | **HTMX** (fast, low maintenance) | ~2 days, `templ` templates, no Node build |
| 2 | **CLI output format default?** | **table** (human-readable) | JSON/YAML/markdown via `--output` flag |
| 3 | **Default task statuses?** | **Fixed: todo / in_progress / done** | Customizable in 0.2+ |
| 4 | **Time tracking in MVP?** | **Skip** | Add in 0.2+ |
| 5 | **Migration from Leantime?** | **Skip** (manual) | Script in 0.2+ |
| 6 | **Config file format?** | **TOML** | viper supports all |
| 7 | **Logging format?** | **JSON structured** (file), **pretty** (CLI) | |
| 8 | **Rate limiting?** | **Per API key** (token bucket) | Per-user/IP in 0.2+ |
| 9 | **Backup/restore CLI?** | **Skip** (pg_dump cron) | Add `momentum backup` in 0.2+ |
| 10 | **Config file location?** | `~/.config/momentum/config.toml` | XDG compliant |
| 11 | **Migration strategy for DB?** | `goose` up/down, versioned | |
| 12 | **API versioning?** | URL prefix `/api/v1/` | |
| 13 | **Secrets management?** | Env vars + `.env` file (dev) | |
| 14 | **Health check endpoint?** | `GET /healthz` + `/readyz` | |

---

## 15. Next Steps

1. **Initialize repo** → `go mod init github.com/buchhalt/momentum`
2. **Write migrations** → `goose create init sql`
3. **Generate sqlc** → `sqlc generate`
4. **Implement auth** → OIDC + JWT middleware
5. **Build task CRUD** → API + CLI parity
6. **Add event store** → all mutations emit events
7. **Dockerize** → multi-stage Dockerfile
8. **CI/CD** → GitHub Actions → goreleaser
9. **Deploy to Unraid** → verify end-to-end

---

*This 0.1 draft is a living document. Update as decisions are made.*