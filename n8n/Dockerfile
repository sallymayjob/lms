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
