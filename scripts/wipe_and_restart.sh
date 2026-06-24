#!/usr/bin/env bash
# Wipe the parksim reckon-db store and restart the container.
#
# Run on each beam node that hosts a parksim instance. Requires sudo
# for the data wipe (store files are owned by the container's root process).
#
# Usage: ssh rl@beamXX.lab 'bash -s' < scripts/wipe_and_restart.sh
#
# Safe to run while other beam nodes are up — the Erlang cluster will
# reform once this node's parksim reconnects.
set -euo pipefail

CONTAINER=parksim
DATA_DIR=/bulk0/hecate/parksim

echo "[wipe-restart] stopping ${CONTAINER}..."
docker stop "${CONTAINER}"

echo "[wipe-restart] wiping store at ${DATA_DIR}..."
sudo rm -rf "${DATA_DIR}"

echo "[wipe-restart] starting ${CONTAINER} (fresh store)..."
docker start "${CONTAINER}"

echo "[wipe-restart] done — tailing logs for 10s to verify startup..."
docker logs -f --since 0s "${CONTAINER}" &
LOGPID=$!
sleep 10
kill "${LOGPID}" 2>/dev/null || true

echo "[wipe-restart] check status:"
docker ps --filter name="${CONTAINER}" --format "  {{.Names}}  {{.Image}}  {{.Status}}"
