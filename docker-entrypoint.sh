#!/bin/bash

set -e

# Fallback: if script doesn't exist in mounted volume, download it
if [ ! -f /usr/local/data/fan_control.sh ]; then
    echo "fan_control.sh not found, downloading default version..."
    curl -sSL https://raw.githubusercontent.com/aZuiZui/unraid-templates/refs/heads/main/fan_control.sh -o /usr/local/data/fan_control.sh
    chmod +x /usr/local/data/fan_control.sh
fi

# Ensure the log file exists
touch /usr/local/data/fan_control.log
chmod 666 /usr/local/data/fan_control.log

# Create cron job
echo "SHELL=/bin/bash" > /etc/cron.d/fan_control
echo "PATH=$PATH" >> /etc/cron.d/fan_control
echo "* * * * * root /usr/local/data/fan_control.sh >> /usr/local/data/fan_control.log 2>&1" >> /etc/cron.d/fan_control
chmod 0644 /etc/cron.d/fan_control

# Export environment for cron
env > /usr/local/bin/env_file

# Start cron in foreground
echo "Starting cron..."
exec cron -f
exec "$@"
