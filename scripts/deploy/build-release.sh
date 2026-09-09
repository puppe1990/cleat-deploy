#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export MIX_ENV=prod
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-buildtime_secret_key_base_32chars_min}"

log() {
  printf '→ %s\n' "$*" >&2
}

main() {
  log "Compiling application"
  mix compile

  log "Building production assets"
  mix assets.deploy

  log "Building OTP release"
  mix release

  log "Release ready at _build/prod/rel/cleat_deploy"
}

main "$@"