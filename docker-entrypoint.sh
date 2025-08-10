#!/bin/bash

set -ex

SCRIPT_PATH="/usr/local/data/fan_control.sh"
SCRIPT_URL="https://raw.githubusercontent.com/aZuiZui/unraid-templates/refs/heads/main/fan_control.sh"

# Ensure curl is installed
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Aborting."; exit 1; }

# Fallback: if script doesn't exist in mounted volume, download it
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "fan_control.sh not found, downloading default version..."
    
    if ! curl -sSL "$SCRIPT_URL" -o "$SCRIPT_PATH"; then
        echo "Failed to download fan_control.sh"
        exit 1
    fi

    chmod +x "$SCRIPT_PATH"
fi

# Keep container running
tail -f /dev/null
