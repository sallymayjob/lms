FROM n8nio/n8n:latest

USER root

# Install required tools:
# - python3: for update-workflow-ids.py
# - curl: for health polling and API calls in entrypoint
# - jq: for JSON manipulation in shell scripts
RUN apk add --no-cache python3 py3-pip curl jq bash

# Install Python requests library for update-workflow-ids.py
RUN pip3 install requests --break-system-packages 2>/dev/null || pip3 install requests

USER node

# Copy pre-import workflows into the image
COPY workflows/ /home/node/workflows/

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
