#!/bin/bash

set -e

# Fallback: if script doesn't exist in mounted volume, download it
if [ ! -f /usr/local/data/fan_control.sh ]; then
    echo "fan_control.sh not found, downloading default version..."
    curl -sSL https://raw.githubusercontent.com/aZuiZui/unraid-templates/refs/heads/main/fan_control.sh -o /usr/local/data/fan_control.sh
    chmod +x /usr/local/data/fan_control.sh
fi
exec "$@"
