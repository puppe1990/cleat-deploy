#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DEPLOY_IP="${DEPLOY_IP:-}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/lightsail-default-key-us-east-1.pem}"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
_cli_deploy_ip="${DEPLOY_IP-}"
_cli_deploy_ssh_key="${DEPLOY_SSH_KEY-}"

if [[ -f "$ROOT/scripts/deploy/deploy.local.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/deploy/deploy.local.env"
fi

if [[ -n "${_cli_deploy_ip}" ]]; then
  DEPLOY_IP="${_cli_deploy_ip}"
fi
if [[ -n "${_cli_deploy_ssh_key}" ]]; then
  DEPLOY_SSH_KEY="${_cli_deploy_ssh_key}"
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

  tarball="$(mktemp -t cleat_deploy_src.XXXXXX.tar.gz)"
  trap 'rm -f "${tarball:-}"' EXIT

  log "Packaging source for server build"
  tar -czf "$tarball" \
    --exclude _build \
    --exclude deps \
    --exclude node_modules \
    --exclude .git \
    --exclude tmp \
    --exclude priv/static/assets \
    -C "$ROOT" .

  log "Uploading source to $DEPLOY_USER@$DEPLOY_IP"
  scp -i "$DEPLOY_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "$tarball" "${DEPLOY_USER}@${DEPLOY_IP}:/tmp/cleat_deploy_src.tar.gz"

  log "Building release on server (linux/amd64)"
  ssh -i "$DEPLOY_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "${DEPLOY_USER}@${DEPLOY_IP}" 'bash -s' <<'REMOTE'
set -euo pipefail

log() { printf '→ %s\n' "$*" >&2; }

if ! command -v mise >/dev/null 2>&1; then
  log "Installing mise + Erlang/Elixir"
  sudo apt-get update
  sudo apt-get install -y curl build-essential git ca-certificates
  curl -fsSL https://mise.run | sh
fi

export PATH="/home/ubuntu/.local/bin:$PATH"
eval "$(/home/ubuntu/.local/bin/mise activate bash)"
mise install erlang@28.4.1 elixir@1.19.5-otp-28
mise use -g erlang@28.4.1 elixir@1.19.5-otp-28

log "Elixir $(elixir --version | head -1)"

rm -rf ~/cleat_deploy_build
mkdir -p ~/cleat_deploy_build
tar -xzf /tmp/cleat_deploy_src.tar.gz -C ~/cleat_deploy_build
cd ~/cleat_deploy_build

export MIX_ENV=prod
export SECRET_KEY_BASE=buildtime_secret_key_base_32chars_min
export TURSO_DATABASE_URL=libsql://build.turso.io

mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
mix compile
mix assets.setup
mix assets.deploy
mix release --overwrite

RELEASE_DIR="/opt/cleat_deploy/releases/build"
sudo mkdir -p "$RELEASE_DIR"
sudo rm -rf "${RELEASE_DIR:?}"/*
sudo cp -a _build/prod/rel/cleat_deploy/. "$RELEASE_DIR/"
sudo ln -sfn "$RELEASE_DIR" /opt/cleat_deploy/current
sudo rm -f /tmp/cleat_deploy_src.tar.gz
log "Server build complete"
REMOTE

  log "Build on panel server finished"
}

main "$@"