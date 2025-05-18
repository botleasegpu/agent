#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO=botleasegpu/agent
SERVICE_NAME=lgpuagent
DATA_DIR=/etc/$SERVICE_NAME

install_binary_latest() {
  local os=$(uname | tr '[:upper:]' '[:lower:]')
  local arch=$(uname -m)
  local latest_tag=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep -Po '"tag_name":\s*"\K.*?(?=")')

  case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "Unsupported arch $arch"; exit 1 ;;
  esac

  local asset="$SERVICE_NAME-$os-$arch"
  local url=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$latest_tag" | \
    grep -Po '"browser_download_url":\s*"\K.*?(?=")' | grep "/$asset$")

  if [[ -z "$url" ]]; then
    echo "Cannot find asset for $asset in release $latest_tag"; exit 1
  fi

  echo "Downloading $asset from $latest_tag…"
  curl -fsSL "$url" -o "/tmp/$asset"
  chmod +x "/tmp/$asset"
  mv "/tmp/$asset" "/usr/local/bin/$SERVICE_NAME"
  mkdir -p "$DATA_DIR"
  echo "$latest_tag" > "$DATA_DIR/version"
}

install_service_unit() {
  cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=$SERVICE_NAME daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/$SERVICE_NAME --token $TOKEN
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF
}

install_update_script() {
  cat > /usr/local/bin/$SERVICE_NAME-update <<EOF
#!/usr/bin/env bash
set -euo pipefail

LATEST=\$(curl -fsSL "https://api.github.com/repos/botleasegpu/agent/releases/latest" | grep -Po '"tag_name":\s*"\K.*?(?=")')
CURRENT=\$(cat "$DATA_DIR/version" 2>/dev/null || echo "")

if [[ "\$LATEST" != "\$CURRENT" ]]; then
  echo "New version \$LATEST (current \$CURRENT), updating…"
  os=\$(uname | tr '[:upper:]' '[:lower:]')
  arch=\$(uname -m)
  [[ "\$arch" == "x86_64" ]] && arch=amd64
  [[ "\$arch" == "aarch64" ]] && arch=arm64
  asset="$SERVICE_NAME-\$os-\$arch"
  url=\$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/tags/\$LATEST" | \
    grep -Po '"browser_download_url":\s*"\K.*?(?=")' | grep "/\$asset$")
  curl -fsSL "\$url" -o "/tmp/\$asset"
  chmod +x "/tmp/\$asset"
  mv "/tmp/\$asset" "/usr/local/bin/$SERVICE_NAME"
  echo "\$LATEST" > "$DATA_DIR/version"
  systemctl restart "$SERVICE_NAME.service"
fi
EOF

  chmod +x "/usr/local/bin/$SERVICE_NAME-update"
}

install_timer_unit() {
  cat > "/etc/systemd/system/$SERVICE_NAME-autoupdater.service" <<EOF
[Unit]
Description=Update $SERVICE_NAME binary

[Service]
Type=oneshot
ExecStart=/usr/local/bin/$SERVICE_NAME-update
EOF

  cat > "/usr/local/bin/$SERVICE_NAME-autoupdater.timer" <<EOF
[Unit]
Description=Run $SERVICE_NAME-autoupdater.service hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

for cmd in curl grep uname systemctl; do
  command -v "$cmd" >/dev/null || { echo "Required command '$cmd' not found"; exit 1; }
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This installer must run as root (sudo)."; exit 1
fi

mkdir -p /usr/local/bin "$DATA_DIR"

install_binary_latest
install_service_unit
install_update_script
install_timer_unit

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.service"
systemctl enable --now "$SERVICE_NAME-autoupdater.timer"

echo "✔ Installed $SERVICE_NAME@$(cat $DATA_DIR/version)"
echo "✔ Service: systemctl status $SERVICE_NAME.service"
echo "✔ Auto-update timer: systemctl list-timers | grep $SERVICE_NAME-autoupdater.timer"
