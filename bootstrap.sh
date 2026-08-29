#!/usr/bin/env bash
# ============================================================
# LLM Router bootstrap — run once, as root, on the engine box.
#   git clone https://github.com/<you>/llm-router /opt/llm-router
#   cd /opt/llm-router && bash bootstrap.sh
#
# Prompts for API keys (they go into /etc/llm-router.env,
# chmod 600, never into the repo), installs a venv + LiteLLM,
# a systemd service on port 4300, and a Caddy HTTPS route.
# Safe to re-run: it upgrades in place and keeps existing keys.
# ============================================================
set -euo pipefail

APP_DIR="/opt/llm-router"
ENV_FILE="/etc/llm-router.env"
DATA_DIR="/var/lib/llm-router"
PORT=4300
HOST_NAME="${ROUTER_HOSTNAME:-llm.5-161-59-25.sslip.io}"

if [[ $EUID -ne 0 ]]; then echo "Run as root."; exit 1; fi

echo "==> Installing system deps"
apt-get update -qq && apt-get install -y -qq python3-venv python3-pip curl >/dev/null

echo "==> Python venv + LiteLLM"
mkdir -p "$APP_DIR" "$DATA_DIR"
[[ -d "$APP_DIR/venv" ]] || python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q --upgrade pip
"$APP_DIR/venv/bin/pip" install -q "litellm[proxy]"

# copy app files if bootstrap is run from a clone elsewhere
if [[ "$(pwd)" != "$APP_DIR" ]]; then
  cp -f config.yaml usage_logger.py stats.py "$APP_DIR/"
fi

echo "==> Keys ($ENV_FILE)"
touch "$ENV_FILE" && chmod 600 "$ENV_FILE"
prompt_key () { # $1=VAR $2=label $3=required(yes/no)
  local var="$1" label="$2" req="$3" cur val
  cur=$(grep -oP "^${var}=\K.*" "$ENV_FILE" 2>/dev/null || true)
  if [[ -n "$cur" ]]; then echo "    $var already set — keeping it."; return; fi
  read -r -s -p "    Paste $label (${req} — Enter to skip): " val; echo
  if [[ -z "$val" && "$req" == "required" ]]; then
    echo "    $label is required."; exit 1
  fi
  [[ -n "$val" ]] && echo "${var}=${val}" >> "$ENV_FILE"
}
prompt_key DEEPSEEK_API_KEY  "DeepSeek API key (platform.deepseek.com)" required
prompt_key ZAI_API_KEY       "Z.AI GLM API key (z.ai, optional fallback)" optional
prompt_key ANTHROPIC_API_KEY "Anthropic API key (optional, powers the 'heavy' tier)" optional

if ! grep -q "^ROUTER_MASTER_KEY=" "$ENV_FILE"; then
  MK="sk-router-$(openssl rand -hex 24)"
  echo "ROUTER_MASTER_KEY=${MK}" >> "$ENV_FILE"
  echo "    Generated router master key (this is what clients use):"
  echo "    ${MK}"
  echo "    (Recover it later with: grep ROUTER_MASTER_KEY $ENV_FILE)"
fi
grep -q "^USAGE_DB=" "$ENV_FILE" || echo "USAGE_DB=${DATA_DIR}/usage.db" >> "$ENV_FILE"

# placeholders so LiteLLM never crashes on a missing optional env var
grep -q "^ZAI_API_KEY=" "$ENV_FILE"       || echo "ZAI_API_KEY=unset" >> "$ENV_FILE"
grep -q "^ANTHROPIC_API_KEY=" "$ENV_FILE" || echo "ANTHROPIC_API_KEY=unset" >> "$ENV_FILE"

echo "==> systemd service"
cat > /etc/systemd/system/llm-router.service <<UNIT
[Unit]
Description=LLM Router (LiteLLM proxy)
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/litellm --config ${APP_DIR}/config.yaml --port ${PORT} --host 127.0.0.1
Restart=always
RestartSec=5
MemoryMax=900M

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now llm-router

echo "==> Caddy route (https://${HOST_NAME})"
if ! grep -q "$HOST_NAME" /etc/caddy/Caddyfile 2>/dev/null; then
  cat >> /etc/caddy/Caddyfile <<CADDY

${HOST_NAME} {
    reverse_proxy 127.0.0.1:${PORT}
}
CADDY
  systemctl reload caddy
fi

echo "==> stats helper"
cat > /usr/local/bin/llm-router-stats <<'STATS'
#!/usr/bin/env bash
exec /opt/llm-router/venv/bin/python /opt/llm-router/stats.py "$@"
STATS
chmod +x /usr/local/bin/llm-router-stats

echo "==> Waiting for the service..."
sleep 4
MK=$(grep -oP "^ROUTER_MASTER_KEY=\K.*" "$ENV_FILE")
if curl -s -m 10 http://127.0.0.1:${PORT}/v1/chat/completions \
     -H "Authorization: Bearer ${MK}" -H "Content-Type: application/json" \
     -d '{"model":"ping","messages":[{"role":"user","content":"ping"}]}' | grep -q "router-ok"; then
  echo ""
  echo "ROUTER IS LIVE ✔  https://${HOST_NAME}"
  echo "Check spend anytime with: llm-router-stats"
else
  echo "Self-test failed — check: journalctl -u llm-router -n 50"
fi
