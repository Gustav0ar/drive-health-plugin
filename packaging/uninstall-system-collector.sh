#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run this uninstaller with sudo." >&2
  exit 1
fi

systemctl disable --now noctalia-smart-monitor.timer 2>/dev/null || true
systemctl stop noctalia-smart-monitor.service 2>/dev/null || true

rm -f \
  /etc/systemd/system/noctalia-smart-monitor.service \
  /etc/systemd/system/noctalia-smart-monitor.timer \
  /usr/local/libexec/noctalia-smart-monitor/collect_raw.sh \
  /usr/local/libexec/noctalia-smart-monitor/smart-action.sh \
  /usr/local/libexec/noctalia-smart-monitor/collect_smart.py
rm -rf /run/noctalia-smart-monitor

systemctl daemon-reload
systemctl reset-failed noctalia-smart-monitor.service 2>/dev/null || true

echo "Removed the Noctalia SMART Monitor system collector."
