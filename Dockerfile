FROM debian:bullseye-slim

# Install necessary packages and Python tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip python3-setuptools python3-dev \
        libusb-1.0-0 \
        nano \
        smartmontools \
        cron \
        build-essential \
        libi2c-dev \
    && pip3 install --no-cache-dir liquidctl \
    && apt-get purge -y build-essential libi2c-dev python3-dev \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts into container
COPY fan_control.sh /usr/local/data/fan_control.sh
COPY startup.sh /usr/local/data/startup.sh

# Ensure scripts are executable
RUN chmod +x /usr/local/data/fan_control.sh /usr/local/data/startup.sh

# Setup cron job
RUN echo "SHELL=/bin/bash" > /etc/cron.d/fan_control && \
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/cron.d/fan_control && \
    echo "* * * * * root /usr/local/data/fan_control.sh >> /var/log/fan_control.log 2>&1" >> /etc/cron.d/fan_control && \
    chmod 0644 /etc/cron.d/fan_control

# Create log file
RUN touch /var/log/fan_control.log && chmod 666 /var/log/fan_control.log

# Set environment path
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

CMD ["bash", "-c", "env > /usr/local/bin/env_file && exec cron -f"]


