#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DEPLOY_IP="${DEPLOY_IP:-}"
DEPLOY_HOST="${DEPLOY_HOST:-paas.gestaobem.com}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/lightsail-default-key-us-east-1.pem}"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
# Preserve CLI overrides — deploy.local.env must not silently win over env vars.
_cli_deploy_ip="${DEPLOY_IP-}"
_cli_deploy_host="${DEPLOY_HOST-}"
_cli_run_seed="${RUN_SEED-}"
RUN_SEED="${RUN_SEED:-false}"
SEED_USER_PASSWORD="${SEED_USER_PASSWORD:-}"
SEED_SSH_KEY_PATH="${SEED_SSH_KEY_PATH:-}"

if [[ -f "$ROOT/scripts/deploy/deploy.local.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/deploy/deploy.local.env"
fi

if [[ -n "${_cli_deploy_ip}" ]]; then
  DEPLOY_IP="${_cli_deploy_ip}"
fi
if [[ -n "${_cli_deploy_host}" ]]; then
  DEPLOY_HOST="${_cli_deploy_host}"
fi
if [[ -n "${_cli_run_seed}" ]]; then
  RUN_SEED="${_cli_run_seed}"
fi

log() {
  printf '→ %s\n' "$*" >&2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

ssh_cmd() {
  ssh -i "$DEPLOY_SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15 \
    "${DEPLOY_USER}@${DEPLOY_IP}" "$@"
}

main() {
  [[ -n "$DEPLOY_IP" ]] || die "Set DEPLOY_IP to the panel Lightsail public IP"
  [[ -f "$DEPLOY_SSH_KEY" ]] || die "SSH key not found: $DEPLOY_SSH_KEY"
  chmod 600 "$DEPLOY_SSH_KEY"

  log "Migrating panel paths from phoenix_paas if needed"
  scp -i "$DEPLOY_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "$ROOT/deploy/cleat_deploy.service" \
    "${DEPLOY_USER}@${DEPLOY_IP}:/tmp/cleat_deploy.service"
  ssh_cmd bash -s <<'REMOTE'
set -euo pipefail
if [[ -d /opt/phoenix_paas && ! -e /opt/cleat_deploy ]]; then
  sudo mv /opt/phoenix_paas /opt/cleat_deploy
fi
if [[ -d /etc/phoenix_paas && ! -e /etc/cleat_deploy ]]; then
  sudo mv /etc/phoenix_paas /etc/cleat_deploy
fi
sudo mv /tmp/cleat_deploy.service /etc/systemd/system/cleat_deploy.service
sudo systemctl daemon-reload
if systemctl list-unit-files | grep -q '^phoenix_paas.service'; then
  sudo systemctl stop phoenix_paas || true
  sudo systemctl disable phoenix_paas || true
fi
sudo systemctl enable cleat_deploy
REMOTE

  "$ROOT/scripts/deploy/build-on-panel-server.sh"

  log "Running migrations"
  ssh_cmd bash -s <<'REMOTE'
set -euo pipefail
if [[ -f /etc/cleat_deploy/env ]]; then
  sudo bash -c 'set -a; source /etc/cleat_deploy/env; set +a; /opt/cleat_deploy/current/bin/migrate'
else
  echo "No /etc/cleat_deploy/env — skipping migrations" >&2
fi
REMOTE

  if [[ "$RUN_SEED" == "true" ]]; then
    log "Running seeds"
    ssh_cmd bash -s <<REMOTE
set -euo pipefail
sudo bash -c "set -a; source /etc/cleat_deploy/env; set +a; export SEED_USER_PASSWORD='${SEED_USER_PASSWORD}'; export SEED_SSH_KEY_PATH='${SEED_SSH_KEY_PATH}'; /opt/cleat_deploy/current/bin/cleat_deploy eval 'CleatDeploy.Release.seed()'"
REMOTE
  fi

  log "Restarting cleat_deploy"
  ssh_cmd "sudo systemctl restart cleat_deploy && sleep 3 && sudo systemctl is-active cleat_deploy"

  log "Panel updated — https://${DEPLOY_HOST}"
}

main "$@"