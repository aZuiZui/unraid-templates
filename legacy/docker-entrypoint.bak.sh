#!/bin/bash

set -e

# Fallback: if script doesn't exist in mounted volume, download it
if [ ! -f /usr/local/data/fan_control.sh ]; then
    echo "fan_control.sh not found, downloading default version..."
    curl -sSL https://raw.githubusercontent.com/aZuiZui/unraid-templates/refs/heads/main/fan_control.sh -o /usr/local/data/fan_control.sh
    chmod +x /usr/local/data/fan_control.sh
fi

# Create cron job (no log output)
echo "SHELL=/bin/bash" > /etc/cron.d/fan_control
echo "PATH=$PATH" >> /etc/cron.d/fan_control
echo "* * * * * root /usr/local/data/fan_control.sh" >> /etc/cron.d/fan_control
chmod 0644 /etc/cron.d/fan_control

# Start cron in foreground
echo "Starting cron..."
exec env > /usr/local/bin/env_file
env > /usr/local/data/env_file2
exec cron -f

