# Multi-tenant Cleat + Turso (prod)

**Date:** 2026-06-18  
**Status:** Proposed — awaiting approval  
**First tenant user:** `matheus.puppe@gmail.com`

## Problem

The panel is single-tenant: no auth, no data isolation, SQLite file in dev/prod. Anyone with the URL sees all servers, SSH keys, and deploy history. Production needs hosted Turso and per-account isolation before public launch.

## Goals

1. **Multi-tenant** — each account sees only its servers, apps, deployments, and env vars.
2. **Turso in prod** — same pattern as `trip-planner-ia-phx` (`ecto_libsql` + `TURSO_DATABASE_URL`).
3. **Auth** — login required for all panel routes; webhooks stay public with HMAC.
4. **Bootstrap** — `matheus.puppe@gmail.com` is the seeded owner of the first org with the existing Trip Planner deploy test data migrated into that tenant.
5. **TDD** — every behaviour below has a failing test written before implementation.

## Non-goals (this phase)

- Billing / Stripe
- Per-tenant Turso databases (one panel DB, row-level tenancy)
- SSO / OAuth (email + password only via `phx.gen.auth`)
- Team invites UI (schema supports memberships; UI can be follow-up)
- Hosting the panel itself (separate deploy task)

## Recommended approach: shared database + `tenant_id`

### Why not one Turso DB per tenant?

Turso-per-tenant fits customer app data, not the control plane. The panel is one product DB with `tenant_id` on every resource — simpler migrations, one connection pool, standard Ecto queries.

### Domain model

```
Tenant (organization)
  ├── has_many TenantMemberships
  ├── has_many Users (through memberships)
  ├── has_many Servers
  └── has_many Apps (through servers)

User
  ├── email (unique globally)
  └── belongs_to many Tenants via TenantMembership (role: owner | admin | member)

Server
  └── tenant_id (required)

App
  └── tenant_id (required) — denormalized for query speed + webhook lookup

Deployment
  └── via app → tenant (no direct tenant_id needed, or add for indexing)

Scope (runtime assign, not DB)
  └── %Scope{tenant: %Tenant{}, user: %User{}, role: :owner}
```

### Tenancy rules

| Rule | Behaviour |
|------|-----------|
| Registration | Creates `User` + `Tenant` + `TenantMembership(role: :owner)` |
| Login | Session stores `user_id`; mount loads active `tenant` (first owned tenant for now) |
| Queries | All context functions take `scope` as first arg: `Servers.list_servers(scope)` |
| Cross-tenant ID | `get_server!(scope, id)` returns `Ecto.NoResultsError` (never leak existence) |
| Uniqueness | `apps.slug` unique per `tenant_id`, not globally |
| `github_repo` | Unique per `tenant_id` (two tenants can deploy same fork) |
| Webhook | Lookup app by `github_repo` + verify signature; app carries `tenant_id` for Oban job |
| SSH keys | Stay encrypted per server; servers scoped by tenant |

### Auth & routes

```
Pipeline :browser
  → fetch_current_scope_for_user   # sets @current_scope or nil

Pipeline :require_authenticated
  → require_authenticated_user     # redirect /users/log-in

live_session :authenticated
  on_mount: {PaasMount, :require_tenant}
  → ensures scope.tenant is set

Public:
  /users/register, /users/log-in, /users/log-out
  POST /webhooks/github
```

LiveViews receive `current_scope` and pass it to context modules. Templates use `@current_scope.user.email`, never `@current_user`.

### Turso (production)

Mirror trip-planner `runtime.exs`:

```elixir
# prod only
if turso_url && String.starts_with?(turso_url, "libsql://") do
  [adapter: Ecto.Adapters.LibSql, uri: turso_url, auth_token: token, pool_size: 10]
else
  [adapter: Ecto.Adapters.LibSql, database: local_fallback, pool_size: 10]
end
```

| Env | DB |
|-----|-----|
| `test` | SQLite in-memory / `cleat_deploy_test.db` (fast, isolated) |
| `dev` | SQLite `cleat_deploy_dev.db` |
| `prod` | Turso via `TURSO_DATABASE_URL` + `TURSO_AUTH_TOKEN` |

Add `{:ecto_libsql, "~> 0.9"}` dependency; keep `ecto_sqlite3` for dev/test.

### Seed: matheus.puppe@gmail.com

`priv/repo/seeds.exs` (prod-safe, idempotent):

1. Upsert user `matheus.puppe@gmail.com` (password from `SEED_USER_PASSWORD` env, or random + log once in dev).
2. Upsert tenant `"Gestão Bem"` (slug: `gestao-bem`).
3. Membership `owner`.
4. Migrate existing single-tenant rows:
   - Server `trip-lightsail` → `tenant_id`
   - App `trip-planner` → `tenant_id`
   - Deployments preserved.

Only this user sees the Trip Planner deploy test in the dashboard.

### Security notes

- `CLOAK_KEY` env for SSH key encryption in prod (replace dev SHA256 hash).
- Webhook endpoint unchanged; no session required.
- Force SSL already in `prod.exs`.
- Rate-limit login (future; not blocking).

## Alternatives considered

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **A. `tenant_id` on rows** | Simple, one migration, familiar Ecto | Must discipline every query | **Recommended** |
| B. Turso DB per tenant | Hard isolation | Connection sprawl, ops nightmare for panel | Reject |
| C. Postgres RLS | DB-enforced | New infra, not Turso | Reject |

## Success criteria

- [ ] `matheus.puppe@gmail.com` logs in and sees Trip Planner + deploy history
- [ ] Second user registers and sees empty dashboard (no cross-tenant leak)
- [ ] `mix test` green with tenancy + auth tests
- [ ] Prod config reads Turso env vars
- [ ] Manual deploy still works with `DEPLOY_RUNNER=ssh` under authenticated session

## Open questions (defaults chosen)

1. **Multi-org per user?** Schema supports it; UI uses first owned tenant only (YAGNI).
2. **Invite flow?** Deferred; only seed user in v1.
3. **Password for seed user?** `SEED_USER_PASSWORD` required in prod seed run.