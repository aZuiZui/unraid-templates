#!/bin/bash
set -e

# Run startup script once on container start
env > /usr/local/data/env_file

# Start cron daemon in foreground to keep container alive
exec cron -f