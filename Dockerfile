FROM debian:bullseye-slim

# Install necessary packages and Python tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        dos2unix \
        python3 python3-pip python3-setuptools python3-dev \
        libusb-1.0-0 \
        nano \
        smartmontools \
        cron \
        build-essential \
        libi2c-dev && \
    pip3 install --no-cache-dir liquidctl && \
    apt-get purge -y build-essential libi2c-dev python3-dev && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Declare volume
VOLUME ["/usr/local/data"]

# Download and fix entrypoint script

ARG CACHE_BUST=1

RUN curl -sSL https://raw.githubusercontent.com/aZuiZui/unraid-templates/refs/heads/main/docker-entrypoint.sh -o /usr/local/bin/docker-entrypoint.sh && \
    dos2unix /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh
	

# Set environment path
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# Setup cron job
RUN echo "SHELL=/bin/bash" > /etc/cron.d/fan_control && \
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/cron.d/fan_control && \
    echo "* * * * * root /usr/local/data/fan_control.sh" >> /etc/cron.d/fan_control && \
    chmod 0644 /etc/cron.d/fan_control
CMD ["bash", "-c", "env > /usr/local/bin/env_file && exec cron -f"]