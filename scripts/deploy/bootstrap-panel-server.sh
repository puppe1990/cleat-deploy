#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DEPLOY_IP="${DEPLOY_IP:-}"
DEPLOY_HOST="${DEPLOY_HOST:-paas.gestaobem.com}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/lightsail-default-key-us-east-1.pem}"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
CADDY_EMAIL="${CADDY_EMAIL:-}"
ENV_FILE="${ENV_FILE:-$ROOT/deploy/env.production}"

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

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ssh_cmd() {
  ssh -i "$DEPLOY_SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15 \
    "${DEPLOY_USER}@${DEPLOY_IP}" "$@"
}

scp_to_server() {
  scp -i "$DEPLOY_SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    "$1" "${DEPLOY_USER}@${DEPLOY_IP}:$2"
}

main() {
  require_command ssh
  require_command scp

  [[ -n "$DEPLOY_IP" ]] || die "Set DEPLOY_IP to the panel Lightsail public IP"
  [[ -f "$DEPLOY_SSH_KEY" ]] || die "SSH key not found: $DEPLOY_SSH_KEY"
  chmod 600 "$DEPLOY_SSH_KEY"

  log "Bootstrapping Cleat panel on $DEPLOY_USER@$DEPLOY_IP"

  scp_to_server "$ROOT/deploy/cleat_deploy.service" "/tmp/cleat_deploy.service"

  if [[ -f "$ENV_FILE" ]]; then
    scp_to_server "$ENV_FILE" "/tmp/cleat_deploy.env"
  else
    log "No env file at $ENV_FILE — copy deploy/env.production.example and retry, or upload /etc/cleat_deploy/env manually"
  fi

  if [[ -n "$DEPLOY_HOST" ]]; then
    cat >"$ROOT/tmp/Caddyfile" <<EOF
{
	email ${CADDY_EMAIL:-admin@${DEPLOY_HOST}}
}

${DEPLOY_HOST} {
	encode gzip
	reverse_proxy 127.0.0.1:4000
}
EOF
    scp_to_server "$ROOT/tmp/Caddyfile" "/tmp/Caddyfile"
  fi

  ssh_cmd "DEPLOY_HOST='${DEPLOY_HOST}' bash -s" <<'REMOTE'
set -euo pipefail

log() { printf '→ %s\n' "$*" >&2; }

if ! swapon --show | grep -q /swapfile; then
  log "Creating 2GB swap"
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

log "Installing deploy runner dependencies (git, openssh-client, tar)"
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git openssh-client tar curl ca-certificates

if ! command -v caddy >/dev/null 2>&1; then
  log "Installing Caddy"
  sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y caddy
fi

sudo mkdir -p /opt/cleat_deploy/releases /etc/cleat_deploy

if [[ -f /tmp/cleat_deploy.env ]]; then
  log "Installing production env"
  sudo mv /tmp/cleat_deploy.env /etc/cleat_deploy/env
  sudo chmod 600 /etc/cleat_deploy/env
fi

sudo mv /tmp/cleat_deploy.service /etc/systemd/system/cleat_deploy.service
sudo systemctl daemon-reload
sudo systemctl enable cleat_deploy

if [[ -n "${DEPLOY_HOST:-}" && -f /tmp/Caddyfile ]]; then
  log "Configuring Caddy for ${DEPLOY_HOST}"
  sudo mkdir -p /etc/caddy
  sudo cp /tmp/Caddyfile /etc/caddy/Caddyfile
  sudo systemctl enable caddy
  sudo systemctl restart caddy
else
  log "DEPLOY_HOST not set — skipping Caddy HTTPS"
fi

log "Bootstrap complete — upload a release with scripts/deploy/update-panel.sh"
REMOTE

  log "Bootstrap finished for $DEPLOY_IP"
}

main "$@"