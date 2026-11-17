#!/usr/bin/env bash
# Stops and removes every drone container started by drones-up.sh.
# Usage: ./scripts/drones-down.sh

# Stop on any failed command (-e), on unset variables (-u),
# and when any command inside a pipe fails, not only the last one (-o pipefail).
set -euo pipefail

# Show usage and exit.
# "${1:-}" gives an empty string when no argument was passed (plain "$1" would fail because of set -u).
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Stops and removes all drone containers started by drones-up.sh."
    exit 0
fi

# drones-up.sh puts this label on every drone container, so we can find all of them at once.
LABEL="drone-sim"

# Use plain docker if we are allowed to talk to the Docker daemon (user is in the "docker" group),
# otherwise fall back to sudo. "docker info" fails when there is no access or the daemon is down.
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

# IDs of all drone containers, running or already stopped (--all), IDs only (--quiet).
ids=$($DOCKER ps --all --quiet --filter "label=$LABEL")

if [[ -z "$ids" ]]; then
    echo "No drone containers found."
else
    echo "Stopping and removing drone containers..."
    # $DOCKER and $ids are unquoted on purpose: bash splits them on whitespace,
    # so "sudo docker" becomes a command plus an argument, and $ids becomes a list of IDs.
    # >/dev/null hides the IDs that docker prints back.
    $DOCKER stop $ids >/dev/null
    $DOCKER rm $ids >/dev/null
    echo "Done."
fi
