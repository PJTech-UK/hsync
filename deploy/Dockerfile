# Production hsync image.
#   docker build -f deploy/Dockerfile -t hsync:latest .
# Build context is the repo root so the package and the loop wrapper are both
# available.
FROM python:3.12-slim

# Run as an unprivileged user. uid 1000 is referenced by the k8s securityContext
# (runAsUser/fsGroup) so the NFS volume can be made writable by it.
RUN useradd -r -u 1000 -m -d /home/hsync hsync

COPY . /src
RUN pip install --no-cache-dir /src \
    && cp /src/deploy/entrypoint.sh /usr/local/bin/hsync-loop \
    && chmod +x /usr/local/bin/hsync-loop \
    && rm -rf /src

USER hsync
ENV HSYNC_DEST=/data \
    HSYNC_INTERVAL=300 \
    HSYNC_HEARTBEAT=/tmp/hsync-heartbeat

# The puller loop. Override with `hsync ...` directly for a one-shot pull.
ENTRYPOINT ["/usr/local/bin/hsync-loop"]
