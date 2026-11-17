#!/usr/bin/env bash
# Starts N ArduPilot SITL copters in Docker, one container per drone.
# Usage: ./scripts/drones-up.sh [count]   (see --help for environment variables)

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Enter the number of drones to start as the first argument."
    echo "Example: ./scripts/drones-up.sh 3 will start 3 drones."
    echo "You can also set the following environment variables:"
    echo "  IMAGE: The docker image to use (default: ardupilot:latest)"
    echo "  ARDUPILOT_DIR: The path to the ardupilot directory (default: current directory/ardupilot)"
    echo "  GCS: The address of the ground control station (default: localhost:14550)"
    echo "  HOME_LAT: The home latitude (default: 52.4064)"
    echo "  HOME_LON: The home longitude (default: 16.9252)"
    echo "  HOME_ALT: The home altitude (default: 80)"
    exit 0
fi

IMAGE="${IMAGE:-ardupilot:latest}"
# Repo root = one level above this script, as an absolute path,
# so the script works no matter which directory it is started from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARDUPILOT_DIR="${ARDUPILOT_DIR:-$REPO_ROOT/ardupilot}"
# Ground control station (e.g. QGroundControl): every drone sends MAVLink telemetry here over UDP.
GCS="${GCS:-127.0.0.1:14550}"
# Home (takeoff) point: latitude, longitude, altitude in meters above sea level. Default is Poznań.
HOME_LAT="${HOME_LAT:-52.4064}"
HOME_LON="${HOME_LON:-16.9252}"
HOME_ALT="${HOME_ALT:-80}"
COUNT="${1:-1}"

if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || (( COUNT > 255 )); then
    echo "Wrong number of drones. Please specify a number between 1 and 255." >&2
    exit 1
fi

# Use plain docker if we are allowed to talk to the Docker daemon (user is in the "docker" group),
# otherwise fall back to sudo. "docker info" fails when there is no access or the daemon is down.
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
fi


# Stop and remove any existing drone containers, so we start fresh.
"$REPO_ROOT/scripts/drones-down.sh"

for ((i = 1; i <= COUNT; i++)); do
    name="drone-$i"
    # SITL instances are numbered from 0. Each instance shifts all its ports by 10 * instance,
    # so several drones on the same host network don't fight over the same ports.
    instance=$(( i - 1 ))

    echo "starting drone $name"
    # Start the simulator in a container. A comment can't sit inside a multi-line command
    # docker run:
    #   --detach            run in the background; docker prints only the container id
    #   --label drone-sim   tag that drones-down.sh uses to find our containers
    #   --network host      share the host network, so SITL ports are reachable on localhost
    #   --volume            mount the ArduPilot folder (with the built SITL binary) into the container
    #   --workdir /tmp      SITL writes eeprom.bin and logs to the current dir; keep them inside
    #                       the container, so every drone starts with fresh parameters
    # arducopter:
    #   --model +           quadcopter in "+" frame
    #   --instance          port offset, see above
    #   --sysid             MAVLink system id, unique per drone so the GCS can tell them apart
    #   --defaults          default copter parameters
    #   --home              lat,lon,alt,heading (heading 0 = facing north)
    #   --serial0           send telemetry from SERIAL0 to the GCS over UDP
    $DOCKER run \
        --detach \
        --name "$name" \
        --label drone-sim \
        --network host \
        --volume "$ARDUPILOT_DIR":/ardupilot \
        --workdir /tmp \
        "$IMAGE" \
        /ardupilot/build/sitl/bin/arducopter \
            --model + \
            --instance "$instance" \
            --sysid "$i" \
            --defaults /ardupilot/Tools/autotest/default_params/copter.parm \
            --home "$HOME_LAT","$HOME_LON","$HOME_ALT",0 \
            --serial0 "udpclient:$GCS" \
        >/dev/null

    # SERIAL1 stays on TCP 5762 (+10 per instance): MAVProxy or a second GCS can connect there.
    echo "drone $name started with sysid $i, TCP port for telemetry: $((5762 + 10 * instance))"
done
