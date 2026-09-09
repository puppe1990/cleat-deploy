#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DEPLOY_IP="${DEPLOY_IP:-}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/lightsail-default-key-us-east-1.pem}"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"

if [[ -f "$ROOT/scripts/deploy/deploy.local.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/deploy/deploy.local.env"
fi

log() {
  printf '→ %s\n' "$*" >&2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

main() {
  [[ -n "$DEPLOY_IP" ]] || die "Set DEPLOY_IP"
  [[ -f "$DEPLOY_SSH_KEY" ]] || die "SSH key not found: $DEPLOY_SSH_KEY"
  chmod 600 "$DEPLOY_SSH_KEY"

  log "Provisioning GitHub webhooks for all apps on $DEPLOY_IP"

  ssh -i "$DEPLOY_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "${DEPLOY_USER}@${DEPLOY_IP}" 'bash -s' <<'REMOTE'
set -euo pipefail

if [[ ! -f /etc/cleat_deploy/env ]]; then
  echo "Error: /etc/cleat_deploy/env not found" >&2
  exit 1
fi

sudo bash -c 'set -a; source /etc/cleat_deploy/env; set +a; /opt/cleat_deploy/current/bin/cleat_deploy rpc "IO.inspect(CleatDeploy.Apps.sync_all_github_webhooks(), label: \"webhook_sync\")"'
REMOTE

  log "GitHub webhook provisioning finished"
}

main "$@"