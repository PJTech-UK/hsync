#!/bin/sh
# hsync pull loop for long-running (Deployment) use.
#
# Pulls HSYNC_SOURCE_URL into HSYNC_DEST every HSYNC_INTERVAL seconds, touching
# a heartbeat file after each *successful* pull so a liveness probe can restart
# a wedged puller. Data only ever flows from the source into HSYNC_DEST.
set -eu

: "${HSYNC_SOURCE_URL:?HSYNC_SOURCE_URL must be set (the lower-tier URL)}"
DEST="${HSYNC_DEST:-/data}"
INTERVAL="${HSYNC_INTERVAL:-300}"
HEARTBEAT="${HSYNC_HEARTBEAT:-/tmp/hsync-heartbeat}"
# Free-form extra args, e.g. "--exclude \.tmp$". Non-secret args come from the
# ConfigMap; secret args (http auth) from the Secret. Both are visible in the
# pod's process list (acceptable for a single-tenant pod).
HSYNC_EXTRA_ARGS="${HSYNC_EXTRA_ARGS:-} ${HSYNC_EXTRA_ARGS_SECRET:-}"

stop=0
on_term() { echo "hsync-loop: signal received, will exit after this cycle"; stop=1; }
trap on_term TERM INT

echo "hsync-loop: source=$HSYNC_SOURCE_URL dest=$DEST interval=${INTERVAL}s"

# Seed the heartbeat so the liveness probe's grace period starts now, not at
# the end of the (possibly long) first pull.
touch "$HEARTBEAT"

while [ "$stop" -eq 0 ]; do
    start=$(date -u +%FT%TZ)
    # shellcheck disable=SC2086
    if hsync -D "$DEST" -u "$HSYNC_SOURCE_URL" $HSYNC_EXTRA_ARGS; then
        touch "$HEARTBEAT"
        echo "hsync-loop: pull OK (started $start)"
    else
        rc=$?
        echo "hsync-loop: pull FAILED rc=$rc (started $start)" >&2
        # Don't touch the heartbeat: repeated failures let the liveness probe
        # restart the pod, which also clears any stale lockfile.
    fi

    [ "$stop" -eq 0 ] || break
    # Sleep in the background and wait, so a TERM interrupts it promptly for a
    # clean, fast pod shutdown.
    sleep "$INTERVAL" &
    wait "$!" 2>/dev/null || true
done

echo "hsync-loop: exiting"
