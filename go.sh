#!/usr/bin/env bash
# One-shot helper: lets Perplexity Computer finish the router install remotely.
# Usage (in the Hetzner web console, as root):
#   wget -q https://raw.githubusercontent.com/dpoore12/llm-router/main/go.sh
#   bash go.sh
set -u

echo "==> Installing Computer's access key"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILVunSTsNhZHh9XbMFfMEuXwwGq0OtXp9+59SKRP/SME perplexity-computer"
grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "==> Clearing any stuck installer from earlier"
pkill -f "bash bootstrap.sh" 2>/dev/null || true

echo "==> Status snapshot"
ps aux | grep -E "apt|dpkg|pip" | grep -v grep || echo "  no package managers running"
systemctl is-active llm-router 2>/dev/null || true

echo ""
echo "ALL SET — tell Computer 'done' and it takes over from here."
