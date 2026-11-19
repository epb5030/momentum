-- name: CreateUser :one
INSERT INTO users (email, name, avatar_url, password_hash, oidc_sub, settings)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id, email, name, avatar_url, password_hash, oidc_sub, settings, created_at, updated_at;

-- name: GetUserByEmail :one
SELECT id, email, name, avatar_url, password_hash, oidc_sub, settings, created_at, updated_at
FROM users
WHERE email = $1 AND deleted_at IS NULL;

-- name: GetUserByID :one
SELECT id, email, name, avatar_url, password_hash, oidc_sub, settings, created_at, updated_at
FROM users
WHERE id = $1 AND deleted_at IS NULL;

-- name: GetUserByOIDCSub :one
SELECT id, email, name, avatar_url, password_hash, oidc_sub, settings, created_at, updated_at
FROM users
WHERE oidc_sub = $1 AND deleted_at IS NULL;

-- name: UpdateUser :one
UPDATE users
SET name = COALESCE($2, name),
    avatar_url = COALESCE($3, avatar_url),
    settings = COALESCE($4, settings),
    updated_at = now()
WHERE id = $1 AND deleted_at IS NULL
RETURNING id, email, name, avatar_url, password_hash, oidc_sub, settings, created_at, updated_at;

-- name: CreateAPIKey :one
INSERT INTO api_keys (user_id, name, key_hash, scopes, expires_at)
VALUES ($1, $2, $3, $4, $5)
RETURNING id, user_id, name, key_hash, scopes, last_used_at, expires_at, created_at;

-- name: GetAPIKeyByHash :one
SELECT id, user_id, name, key_hash, scopes, last_used_at, expires_at, created_at
FROM api_keys
WHERE key_hash = $1 AND (expires_at IS NULL OR expires_at > now());

-- name: UpdateAPIKeyLastUsed :exec
UPDATE api_keys
SET last_used_at = now()
WHERE id = $1;

-- name: ListAPIKeys :many
SELECT id, user_id, name, scopes, last_used_at, expires_at, created_at
FROM api_keys
WHERE user_id = $1 AND (expires_at IS NULL OR expires_at > now())
ORDER BY created_at DESC;

-- name: DeleteAPIKey :exec
DELETE FROM api_keys WHERE id = $1 AND user_id = $2;

-- name: CreateWorkspace :one
INSERT INTO workspaces (name, owner_id, settings)
VALUES ($1, $2, $3)
RETURNING id, name, owner_id, settings, created_at;

-- name: GetWorkspace :one
SELECT id, name, owner_id, settings, created_at
FROM workspaces
WHERE id = $1;

-- name: ListWorkspacesByUser :many
SELECT w.id, w.name, w.owner_id, w.settings, w.created_at
FROM workspaces w
JOIN workspace_members wm ON w.id = wm.workspace_id
WHERE wm.user_id = $1
ORDER BY w.created_at DESC;

-- name: AddWorkspaceMember :exec
INSERT INTO workspace_members (workspace_id, user_id, role)
VALUES ($1, $2, $3)
ON CONFLICT (workspace_id, user_id) DO UPDATE SET role = EXCLUDED.role;

-- name: GetWorkspaceMembers :many
SELECT wm.workspace_id, wm.user_id, wm.role, wm.joined_at, u.email, u.name
FROM workspace_members wm
JOIN users u ON u.id = wm.user_id
WHERE wm.workspace_id = $1;

-- name: UpdateWorkspaceMemberRole :exec
UPDATE workspace_members
SET role = $3
WHERE workspace_id = $1 AND user_id = $2;

-- name: RemoveWorkspaceMember :exec
DELETE FROM workspace_members WHERE workspace_id = $1 AND user_id = $2;

-- name: CreateProject :one
INSERT INTO projects (workspace_id, name, description, color, icon, settings, created_by)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING id, workspace_id, name, description, color, icon, archived_at, settings, created_by, created_at, updated_at;

-- name: GetProject :one
SELECT id, workspace_id, name, description, color, icon, archived_at, settings, created_by, created_at, updated_at
FROM projects
WHERE id = $1;

-- name: ListProjectsByWorkspace :many
SELECT id, workspace_id, name, description, color, icon, archived_at, settings, created_by, created_at, updated_at
FROM projects
WHERE workspace_id = $1 AND archived_at IS NULL
ORDER BY created_at DESC;

-- name: UpdateProject :one
UPDATE projects
SET name = COALESCE($2, name),
    description = COALESCE($3, description),
    color = COALESCE($3, color),
    icon = COALESCE($4, icon),
    settings = COALESCE($5, settings),
    updated_at = now()
WHERE id = $1
RETURNING id, workspace_id, name, description, color, icon, archived_at, settings, created_by, created_at, updated_at;

-- name: ArchiveProject :exec
UPDATE projects SET archived_at = now(), updated_at = now() WHERE id = $1;

-- name: CreateTask :one
INSERT INTO tasks (project_id, parent_id, title, description_md, status, priority, assignee_id, reporter_id, due_at, start_at, position, recurrence_rule, recurrence_parent_id, metadata)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
RETURNING id, project_id, parent_id, title, description_md, status, priority, assignee_id, reporter_id, due_at, start_at, completed_at, position, recurrence_rule, recurrence_parent_id, metadata, created_at, updated_at, deleted_at;

-- name: GetTask :one
SELECT id, project_id, parent_id, title, description_md, status, priority, assignee_id, reporter_id, due_at, start_at, completed_at, position, recurrence_rule, recurrence_parent_id, metadata, created_at, updated_at, deleted_at
FROM tasks
WHERE id = $1 AND deleted_at IS NULL;

-- name: ListTasksByProject :many
SELECT id, project_id, parent_id, title, description_md, status, priority, assignee_id, reporter_id, due_at, start_at, completed_at, position, recurrence_rule, recurrence_parent_id, metadata, created_at, updated_at, deleted_at
FROM tasks
WHERE project_id = $1 AND deleted_at IS NULL
ORDER BY position ASC, created_at ASC;

-- name: ListTasksByAssignee :many
SELECT id, project_id, parent_id, title, description_md, status, priority, assignee_id, reporter_id, due_at, start_at, completed_at, position, recurrence_rule, recurrence_parent_id, metadata, created_at, updated_at, deleted_at
FROM tasks
WHERE assignee_id = $1 AND deleted_at IS NULL
ORDER BY due_at ASC NULLS LAST, position ASC;

-- name: UpdateTask :one
UPDATE tasks
SET title = COALESCE($2, title),
    description_md = COALESCE($3, description_md),
    status = COALESCE($3, status),
    priority = COALESCE($4, priority),
    assignee_id = COALESCE($5, assignee_id),
    due_at = COALESCE($6, due_at),
    start_at = COALESCE($7, start_at),
    completed_at = COALESCE($8, completed_at),
    position = COALESCE($9, position),
    metadata = COALESCE($10, metadata),
    updated_at = now()
WHERE id = $1 AND deleted_at IS NULL
RETURNING id, project_id, parent_id, title, description_md, status, priority, assignee_id, reporter_id, due_at, start_at, completed_at, position, recurrence_rule, recurrence_parent_id, metadata, created_at, updated_at, deleted_at;

-- name: DeleteTask :exec
UPDATE tasks SET deleted_at = now(), updated_at = now() WHERE id = $1;

-- name: AddTaskDependency :exec
INSERT INTO task_dependencies (task_id, depends_on_id, type)
VALUES ($1, $2, $3)
ON CONFLICT (task_id, depends_on_id) DO UPDATE SET type = EXCLUDED.type;

-- name: RemoveTaskDependency :exec
DELETE FROM task_dependencies WHERE task_id = $1 AND depends_on_id = $2;

-- name: GetTaskDependencies :many
SELECT td.task_id, td.depends_on_id, td.type, td.created_at, t.title as depends_on_title
FROM task_dependencies td
JOIN tasks t ON t.id = td.depends_on_id
WHERE td.task_id = $1;

-- name: CreateTag :one
INSERT INTO tags (workspace_id, name, color)
VALUES ($1, $2, $3)
RETURNING id, workspace_id, name, color, created_at;

-- name: GetTagsByWorkspace :many
SELECT id, workspace_id, name, color, created_at
FROM tags
WHERE workspace_id = $1
ORDER BY name;

-- name: AddTaskTag :exec
INSERT INTO task_tags (task_id, tag_id)
VALUES ($1, $2)
ON CONFLICT (task_id, tag_id) DO NOTHING;

-- name: RemoveTaskTag :exec
DELETE FROM task_tags WHERE task_id = $1 AND tag_id = $2;

-- name: GetTaskTags :many
SELECT t.id, t.workspace_id, t.name, t.color, t.created_at
FROM tags t
JOIN task_tags tt ON tt.tag_id = t.id
WHERE tt.task_id = $1;

-- name: CreateComment :one
INSERT INTO comments (task_id, user_id, content_md)
VALUES ($1, $2, $3)
RETURNING id, task_id, user_id, content_md, created_at, updated_at, deleted_at;

-- name: GetCommentsByTask :many
SELECT id, task_id, user_id, content_md, created_at, updated_at, deleted_at
FROM comments
WHERE task_id = $1 AND deleted_at IS NULL
ORDER BY created_at ASC;

-- name: UpdateComment :one
UPDATE comments
SET content_md = $2, updated_at = now()
WHERE id = $1 AND deleted_at IS NULL
RETURNING id, task_id, user_id, content_md, created_at, updated_at, deleted_at;

-- name: DeleteComment :exec
UPDATE comments SET deleted_at = now(), updated_at = now() WHERE id = $1;

-- name: CreateEvent :one
INSERT INTO events (aggregate_type, aggregate_id, event_type, payload, user_id, ip, user_agent, request_id)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, aggregate_type, aggregate_id, event_type, payload, user_id, ip, user_agent, request_id, created_at;

-- name: GetEventsByAggregate :many
SELECT id, aggregate_type, aggregate_id, event_type, payload, user_id, ip, user_agent, request_id, created_at
FROM events
WHERE aggregate_type = $1 AND aggregate_id = $2
ORDER BY created_at DESC;

-- name: GetEventsByUser :many
SELECT id, aggregate_type, aggregate_id, event_type, payload, user_id, ip, user_agent, request_id, created_at
FROM events
WHERE user_id = $1
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: CreateWorkspaceMember :exec
INSERT INTO workspace_members (workspace_id, user_id, role)
VALUES ($1, $2, $3)
ON CONFLICT (workspace_id, user_id) DO UPDATE SET role = EXCLUDED.role;

-- name: GetWorkspaceMember :one
SELECT workspace_id, user_id, role, joined_at
FROM workspace_members
WHERE workspace_id = $1 AND user_id = $2;

-- name: ListWorkspaceMembers :many
SELECT wm.workspace_id, wm.user_id, wm.role, wm.joined_at, u.email, u.name
FROM workspace_members wm
JOIN users u ON u.id = wm.user_id
WHERE wm.workspace_id = $1;

-- name: UpdateWorkspaceMember :exec
UPDATE workspace_members SET role = $3 WHERE workspace_id = $1 AND user_id = $2;