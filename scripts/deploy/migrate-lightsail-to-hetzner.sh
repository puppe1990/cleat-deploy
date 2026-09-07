#!/usr/bin/env bash
# Copy Phoenix + Go apps from Lightsail onto the Hetzner CX33.
#
# Required:
#   HETZNER_SERVER_IP
# Optional:
#   CATALOGO_SERVER_IP (default 52.73.89.19)
#   ATELIE_SERVER_IP   (default 3.211.110.141)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/scripts/deploy/deploy.local.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/deploy/deploy.local.env"
fi

HETZNER_IP="${HETZNER_SERVER_IP:-}"
CATALOGO_IP="${CATALOGO_SERVER_IP:-52.73.89.19}"
ATELIE_IP="${ATELIE_SERVER_IP:-3.211.110.141}"
SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/lightsail-default-key-us-east-1.pem}"
SSH_USER="${DEPLOY_USER:-ubuntu}"

# phoenix_paas is built separately on the CX33 — do not overwrite it with the Lightsail release.
PHOENIX_APPS=(assistente catalog_platform festa_platform open_drive pay_core vexo)
GO_APPS_CATALOGO=(leilao-erp trama-bras)
GO_APPS_ATELIE=(atelie)

log() { printf '→ %s\n' "$*" >&2; }
die() { echo "Error: $*" >&2; exit 1; }

[[ -n "$HETZNER_IP" ]] || die "Set HETZNER_SERVER_IP to the CX33 public IPv4"
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"
chmod 600 "$SSH_KEY"

ssh_opts=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)

ssh_src() {
  local ip="$1"
  shift
  ssh "${ssh_opts[@]}" "${SSH_USER}@${ip}" "$@"
}

ssh_dst() {
  ssh "${ssh_opts[@]}" "${SSH_USER}@${HETZNER_IP}" "$@"
}

copy_path() {
  local src_ip="$1" src_path="$2" dst_path="${3:-$2}"
  log "copy $src_ip:$src_path -> $HETZNER_IP:$dst_path"
  ssh_dst "sudo mkdir -p $dst_path"
  ssh_src "$src_ip" "sudo tar -C $(dirname "$src_path") -czf - $(basename "$src_path")" |
    ssh_dst "sudo tar -C $(dirname "$dst_path") -xzf -"
}

copy_file() {
  local src_ip="$1" src_path="$2" dst_path="${3:-$2}"
  log "copy $src_ip:$src_path -> $HETZNER_IP:$dst_path"
  ssh_dst "sudo mkdir -p $(dirname "$dst_path")"
  ssh_src "$src_ip" "sudo cat $src_path" |
    ssh_dst "sudo tee $dst_path >/dev/null"
}

enable_unit() {
  local unit="$1"
  ssh_dst "sudo systemctl daemon-reload && sudo systemctl enable --now $unit || true"
}

copy_sqlite() {
  local src_ip="$1" db_path="$2"
  if ! ssh_src "$src_ip" "sudo test -f $db_path"; then
    return 0
  fi
  log "sqlite snapshot $src_ip:$db_path"
  ssh_src "$src_ip" "sudo apt-get -qq install -y sqlite3 >/dev/null 2>&1 || true; sudo sqlite3 $db_path \".backup '/tmp/paas_sqlite.bak'\""
  ssh_dst "sudo mkdir -p $(dirname "$db_path")"
  ssh_src "$src_ip" "sudo cat /tmp/paas_sqlite.bak" | ssh_dst "sudo dd of=$db_path status=none"
  ssh_src "$src_ip" "sudo rm -f /tmp/paas_sqlite.bak"
}

main() {
  log "Migrating Lightsail workloads to Hetzner $HETZNER_IP"

  ssh_dst "id leilao >/dev/null 2>&1 || sudo useradd --system --create-home --shell /usr/sbin/nologin leilao"

  for app in "${PHOENIX_APPS[@]}"; do
    copy_path "$CATALOGO_IP" "/opt/$app" "/opt/$app"
    copy_file "$CATALOGO_IP" "/etc/$app/env" "/etc/$app/env"
    copy_file "$CATALOGO_IP" "/etc/systemd/system/$app.service" "/etc/systemd/system/$app.service"
    if ssh_src "$CATALOGO_IP" "test -d /var/lib/$app"; then
      copy_path "$CATALOGO_IP" "/var/lib/$app" "/var/lib/$app"
    fi
    ssh_dst "sudo chmod 600 /etc/$app/env"
    copy_sqlite "$CATALOGO_IP" "/var/lib/$app/${app}.db"
    copy_sqlite "$CATALOGO_IP" "/var/lib/$app/${app}_prod.db"
    copy_sqlite "$CATALOGO_IP" "/var/lib/$app/replica.db"
    enable_unit "$app"
  done

  copy_sqlite "$CATALOGO_IP" "/var/lib/festa_platform/festa_platform_prod.db"
  copy_sqlite "$CATALOGO_IP" "/var/lib/pay_core/pay_core.db"
  copy_sqlite "$CATALOGO_IP" "/var/lib/vexo/vexo.db"
  copy_sqlite "$CATALOGO_IP" "/var/lib/assistente/replica.db"

  for app in "${GO_APPS_CATALOGO[@]}"; do
    copy_path "$CATALOGO_IP" "/opt/$app" "/opt/$app"
    copy_file "$CATALOGO_IP" "/etc/$app/env" "/etc/$app/env"
    copy_file "$CATALOGO_IP" "/etc/systemd/system/$app.service" "/etc/systemd/system/$app.service"
    if ssh_src "$CATALOGO_IP" "test -d /var/lib/$app"; then
      copy_path "$CATALOGO_IP" "/var/lib/$app" "/var/lib/$app"
    fi
    ssh_dst "sudo chmod 600 /etc/$app/env"
    copy_sqlite "$CATALOGO_IP" "/opt/$app/data/app.db"
    copy_sqlite "$CATALOGO_IP" "/var/lib/$app/app.db"
    enable_unit "$app"
  done

  for app in "${GO_APPS_ATELIE[@]}"; do
    copy_path "$ATELIE_IP" "/opt/$app" "/opt/$app"
    copy_file "$ATELIE_IP" "/etc/$app/env" "/etc/$app/env"
    copy_file "$ATELIE_IP" "/etc/systemd/system/$app.service" "/etc/systemd/system/$app.service"
    if ssh_src "$ATELIE_IP" "test -f /etc/systemd/system/${app}-worker.service"; then
      copy_file "$ATELIE_IP" "/etc/systemd/system/${app}-worker.service" "/etc/systemd/system/${app}-worker.service"
    fi
    ssh_dst "sudo chmod 600 /etc/$app/env"
    copy_sqlite "$ATELIE_IP" "/opt/$app/data/app.db"
    # Dedicated Ateliê used :8080; Leilão ERP already occupies 8080 on the shared host.
    ssh_dst "sudo sed -i 's/^PORT=.*/PORT=:4020/' /etc/atelie/env"
    enable_unit "$app"
    enable_unit "${app}-worker"
  done

  log "Installing Caddyfile from catalogo (auto TLS; drop custom atelie certs)"
  ssh_src "$CATALOGO_IP" "sudo cat /etc/caddy/Caddyfile" > /tmp/paas-caddyfile
  python3 - <<'PY'
from pathlib import Path
text = Path("/tmp/paas-caddyfile").read_text()
# Dedicated atelie used a static cert; Caddy on Hetzner should issue Let's Encrypt.
text = text.replace("  tls /etc/caddy/certs/fullchain.pem /etc/caddy/certs/privkey.pem\n", "")
Path("/tmp/paas-caddyfile").write_text(text)
PY
  scp "${ssh_opts[@]}" /tmp/paas-caddyfile "${SSH_USER}@${HETZNER_IP}:/tmp/Caddyfile"
  ssh_dst "sudo cp /tmp/Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy || sudo systemctl restart caddy"

  log "Active units on Hetzner:"
  ssh_dst "systemctl is-active ${PHOENIX_APPS[*]} ${GO_APPS_CATALOGO[*]} atelie atelie-worker caddy || true"

  cat <<EOF

Migration copied. DNS is still on Lightsail until you flip Hostinger A records.

Update these A records to $HETZNER_IP:
  paas.gestaobem.com
  loja.gestaobem.com
  vexo.gestaobem.com
  decor.gestaobem.com
  pay.gestaobem.com
  drive.gestaobem.com
  clarity.gestaobem.com
  atelie.gestaobem.com
  trama.gestaobem.com
  eletronicos.gestaobem.com

Then on the panel:
  HETZNER_SERVER_IP=$HETZNER_IP bin/phoenix_paas rpc "Code.eval_file(\\"priv/scripts/setup_hetzner.exs\\")"

Leave Lightsail running until HTTPS and health checks pass on Hetzner.
EOF
}

main "$@"
