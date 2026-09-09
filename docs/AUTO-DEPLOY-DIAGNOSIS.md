# Auto-deploy diagnosis (Cleat)

## How auto-deploy is supposed to work

```
GitHub push (main)
  → POST https://paas.gestaobem.com/webhooks/github  (HMAC secret)
  → GithubWebhookController (signature + branch + auto_deploy)
  → Deployments.enqueue → Oban queue :deploys
  → DeployWorker → SshRunner
  → clone, mix release, cp _build/prod/rel/<release_name>, systemd restart
```

## Decor failure (2026-08)

### Symptoms
- Merge to `gestao-bem/gestao-bem-decor` `main` did **not** update https://decor.gestaobem.com
- Manual deploy from laptop (local SQLite) sometimes looked fine; production panel Turso still failed

### Root causes (confirmed in prod)

| # | Issue | Evidence |
|---|--------|----------|
| 1 | **Wrong OTP release name** | Deploy log: `cp: cannot stat '_build/prod/rel/decor/.'` while Mix app is `:festa_platform` |
| 2 | **Wrong target server** | App `decor` on prod pointed to `campanha-lightsail` `52.0.157.89`; DNS A record is `52.73.89.19` |
| 3 | **Panel code stale** | Production `App.release_name("decor")` returned `"decor"` (no special-case mapping deployed) |
| 4 | Webhook **does** fire | GitHub deliveries `202 queued` / logs `POST /webhooks/github` → `Sent 202` |

So auto-deploy **queued and ran**, then **failed** mid-copy on the wrong host.

### Fixes shipped
1. `App.release_name("decor") → "festa_platform"` (+ systemd/path defaults)
2. Resolve `release_name` from **mix.exs** `app:` atom when present
3. Fail early with `ls _build/prod/rel` if release dir missing
4. `setup_decor.exs` / `deploy_decor.exs` use `decor-lightsail` @ DNS IP
5. Webhook controller: no 500 on missing `repository`; better logging

### Ops checklist after panel deploy
```bash
# On paas host
./bin/cleat_deploy rpc 'IO.inspect(CleatDeploy.Apps.App.release_name("decor"))'
# => "festa_platform"

# Fix decor server if still wrong (prefer setup_decor.exs with prod env)
# Then re-deploy decor from panel UI or deploy_decor.exs
```

### Smoke after auto-deploy
```bash
curl -sL https://decor.gestaobem.com/ | grep -o 'Sistema para Decoradoras' | head -1
curl -sL -o /dev/null -w '%{http_code}\n' https://decor.gestaobem.com/pegue-e-monte
```
