FROM n8nio/n8n:latest

USER root

# install required tools (Debian-based image uses apt, not apk)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    jq \
    bash \
 && rm -rf /var/lib/apt/lists/*

USER node

# Copy pre-import workflows into the image
COPY workflows/ /home/node/workflows/

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Ensure entrypoint is executable (git may not preserve +x bit)
USER root
RUN chmod +x /entrypoint.sh
USER node

ENTRYPOINT ["/entrypoint.sh"]
