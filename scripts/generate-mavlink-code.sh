#!/usr/bin/env bash
# Generates the C# MAVLink library (message structs, enums, parser, CRC) into src/Mavlink.
# Runs pymavlink's mavgen in a throwaway Python container, so nothing is installed on the host.
# Dialect: ardupilotmega.xml (includes common.xml), wire protocol MAVLink 2.
# Only the generated .cs files are copied, so the hand-edited MAVLink.csproj is left untouched.
# Usage: ./scripts/generate-mavlink-code.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAVLINK_DIR="$REPO_ROOT/src/Mavlink"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

mkdir -p $MAVLINK_DIR

$DOCKER run --rm --user "$(id -u):$(id -g)" \
  --volume "$TMP_DIR":/out python:3.13-slim sh -c '
    pip install -q --no-cache-dir --target /tmp/pm pymavlink &&
    PYTHONPATH=/tmp/pm python -m pymavlink.tools.mavgen --lang=CS --wire-protocol=2.0 \
      -o /out /tmp/pm/pymavlink/dialects/v20/ardupilotmega.xml'

cp "$TMP_DIR"/*.cs "$MAVLINK_DIR"/

echo "MAVLink C# code generated in $MAVLINK_DIR"