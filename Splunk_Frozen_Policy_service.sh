#!/bin/bash
# Install systemd oneshot + timer for Splunk Frozen Retention Policy v1.1.0

set -euo pipefail

SERVICE_PATH="/etc/systemd/system/Splunk_Frozen_Policy.service"
TIMER_PATH="/etc/systemd/system/Splunk_Frozen_Policy.timer"
SCRIPT_PATH="${SCRIPT_PATH:-/root/scripts/Splunk_Frozen_Retention_Policy.sh}"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: retention script not found: $SCRIPT_PATH" >&2
    exit 1
fi

cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Splunk Frozen Policy Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_PATH
User=root
Nice=10
StandardOutput=journal
StandardError=journal
EOF

cat >"$TIMER_PATH" <<EOF
[Unit]
Description=Run Splunk Frozen Policy Service every 24 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=24h
Unit=Splunk_Frozen_Policy.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

chmod 750 "$SCRIPT_PATH"

systemctl daemon-reload
# Timer-only enable: avoid dual boot start via WantedBy=multi-user on the service unit
systemctl disable Splunk_Frozen_Policy.service 2>/dev/null || true
systemctl enable Splunk_Frozen_Policy.timer
systemctl start Splunk_Frozen_Policy.timer

echo "Timer created and started successfully (oneshot service, timer-only enable)."
echo "Check status with: systemctl status Splunk_Frozen_Policy.timer"
