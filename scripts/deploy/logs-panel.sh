#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -f "$ROOT/scripts/deploy/deploy.local.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/deploy/deploy.local.env"
fi

DEPLOY_IP="${DEPLOY_IP:-}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/lightsail-default-key-us-east-1.pem}"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
LINES="${1:-100}"
FOLLOW="${FOLLOW:-false}"

if [[ -z "$DEPLOY_IP" ]]; then
  echo "Set DEPLOY_IP in scripts/deploy/deploy.local.env" >&2
  exit 1
fi

SSH=(ssh -i "$DEPLOY_SSH_KEY" -o StrictHostKeyChecking=accept-new "${DEPLOY_USER}@${DEPLOY_IP}")

if [[ "$FOLLOW" == "true" ]]; then
  "${SSH[@]}" "sudo journalctl -u cleat_deploy -u phoenix_paas -n ${LINES} -f --no-pager"
else
  "${SSH[@]}" "sudo journalctl -u cleat_deploy -u phoenix_paas -n ${LINES} --no-pager"
fi