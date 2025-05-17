#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO=botleasegpu/agent
SERVICE_NAME=lgpuagent
DATA_DIR=/etc/$SERVICE_NAME

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This uninstaller must run as root (sudo)."
  exit 1
fi

echo "Stopping and disabling systemd units..."
systemctl stop "$SERVICE_NAME-autoupdater.timer" 2>/dev/null || true
systemctl disable "$SERVICE_NAME-autoupdater.timer" 2>/dev/null || true
systemctl stop "$SERVICE_NAME.service" 2>/dev/null || true
systemctl disable "$SERVICE_NAME.service" 2>/dev/null || true

rm -f "/usr/local/bin/$SERVICE_NAME"
rm -f "/usr/local/bin/$SERVICE_NAME-update"
rm -f "/etc/systemd/system/$SERVICE_NAME.service"
rm -f "/etc/systemd/system/$SERVICE_NAME-autoupdater.timer"
rm -f "/etc/systemd/system/$SERVICE_NAME-autoupdater.service"
rm -f "$DATA_DIR/version"

if [[ $REMOVE_DATA == true ]]; then
  echo "Removing data directory..."
  rm -f "$DATA_DIR"
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "✔ Uninstalled $SERVICE_NAME"
