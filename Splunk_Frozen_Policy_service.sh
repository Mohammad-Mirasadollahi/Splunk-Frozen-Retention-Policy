#!/bin/bash

# Variables
SERVICE_PATH="/etc/systemd/system/Splunk_Frozen_Policy.service"
SCRIPT_PATH="/root/scripts/Splunk_Frozen_Retention_Policy.sh"
TIMER_PATH="/etc/systemd/system/Splunk_Frozen_Policy.timer"

# Create the service file
echo "[Unit]
Description=Splunk Frozen Policy Service
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
User=root
Restart=on-failure
RestartSec=30s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target" > $SERVICE_PATH

# Create the timer file
echo "[Unit]
Description=Run Splunk Frozen Policy Service every 24 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=24h

[Install]
WantedBy=timers.target" > $TIMER_PATH

# Give execution permissions to the script
chmod 750 $SCRIPT_PATH

# Reload the systemd daemon, enable and start the service and timer
systemctl daemon-reload
systemctl enable Splunk_Frozen_Policy.service
systemctl enable Splunk_Frozen_Policy.timer
systemctl start Splunk_Frozen_Policy.timer

echo "Service and timer created and started successfully."
