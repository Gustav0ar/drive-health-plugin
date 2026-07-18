#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run this installer with sudo." >&2
  exit 1
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for dependency in sh smartctl lsblk systemctl; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing required command: $dependency" >&2
    exit 1
  fi
done

install -Dm0755 \
  "$project_dir/scripts/collect_raw.sh" \
  /usr/local/libexec/noctalia-smart-monitor/collect_raw.sh
install -Dm0755 \
  "$project_dir/packaging/smart-action.sh" \
  /usr/local/libexec/noctalia-smart-monitor/smart-action.sh
install -Dm0644 \
  "$project_dir/packaging/noctalia-smart-monitor.service" \
  /etc/systemd/system/noctalia-smart-monitor.service
install -Dm0644 \
  "$project_dir/packaging/noctalia-smart-monitor.timer" \
  /etc/systemd/system/noctalia-smart-monitor.timer

systemctl daemon-reload
systemctl enable --now noctalia-smart-monitor.timer
systemctl start noctalia-smart-monitor.service

# Removed only after the replacement service has completed successfully.
rm -f /usr/local/libexec/noctalia-smart-monitor/collect_smart.py

echo "Installed the read-only SMART collector."
echo "Cache: /run/noctalia-smart-monitor/raw.json"
