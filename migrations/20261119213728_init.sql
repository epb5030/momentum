-- +goose Up
-- +goose StatementBegin

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

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
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id              UUID REFERENCES projects(id) ON DELETE CASCADE,
    parent_id               UUID REFERENCES tasks(id) ON DELETE SET NULL,
    title                   TEXT NOT NULL,
    description_md          TEXT,
    status                  TEXT NOT NULL DEFAULT 'todo',
    priority                INTEGER DEFAULT 0,
    assignee_id             UUID REFERENCES users(id) ON DELETE SET NULL,
    reporter_id             UUID REFERENCES users(id),
    due_at                  TIMESTAMPTZ,
    start_at                TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    position                INTEGER DEFAULT 0,
    recurrence_rule         TEXT,
    recurrence_parent_id    UUID REFERENCES tasks(id),
    metadata                JSONB DEFAULT '{}',
    created_at              TIMESTAMPTZ DEFAULT now(),
    updated_at              TIMESTAMPTZ DEFAULT now(),
    deleted_at              TIMESTAMPTZ
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

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TABLE IF EXISTS plugin_configs;
DROP TABLE IF EXISTS plugins;
DROP TABLE IF EXISTS webhooks;
DROP TABLE IF EXISTS agent_sessions;
DROP TABLE IF EXISTS task_embeddings;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS attachments;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS task_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS task_dependencies;
DROP TABLE IF EXISTS tasks;
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS workspace_members;
DROP TABLE IF EXISTS workspaces;
DROP TABLE IF EXISTS api_keys;
DROP TABLE IF EXISTS users;
DROP EXTENSION IF EXISTS vector;

-- +goose StatementEnd