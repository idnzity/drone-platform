#!/usr/bin/env bash
# Starts N ArduPilot SITL copters in Docker, one container per drone.
# Usage: ./scripts/drones-up.sh [count]   (see --help for environment variables)

# Stop on any failed command (-e), on unset variables (-u),
# and when any command inside a pipe fails, not only the last one (-o pipefail).
set -euo pipefail

# Show usage and exit.
# "${1:-}" gives an empty string when no argument was passed (plain "$1" would fail because of set -u).
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


# Settings. Each one can be overridden from the environment, e.g. IMAGE=my-image ./scripts/drones-up.sh
# "${VAR:-default}" means: take $VAR if it is set and not empty, otherwise use the default.
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
# Number of drones: the first argument, 1 if none was given.
COUNT="${1:-1}"

# One container per drone: drone-1, drone-2, ...
for((i = 1; i <= COUNT; i++)); do
  name="drone-$i"
  # SITL instances are numbered from 0. Each instance shifts all its ports by 10 * instance,
  # so several drones on the same host network don't fight over the same ports.
   instance=$(( i - 1 ))

  # Remove an old container with the same name, if any. "|| true" ignores the error when there is none.
  docker rm --force "$name" >/dev/null 2>&1 || true

  echo "starting drone $name"
  # Start the simulator in a container. A comment can't sit inside a multi-line command
  # (the "\" must be the last character on the line), so the flags are explained here.
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
  # >/dev/null hides the container id that docker prints.
  docker run \
   --detach \
    --name "$name"\
    --label drone-sim\
      --network host \
     --volume "$ARDUPILOT_DIR":/ardupilot \
     --workdir /tmp \
     "$IMAGE" \
    /ardupilot/build/sitl/bin/arducopter --model + \
    --instance "$instance" \
    --sysid "$i" \
    --defaults /ardupilot/Tools/autotest/default_params/copter.parm \
      --home "$HOME_LAT","$HOME_LON","$HOME_ALT",0 \
    --serial0 "udpclient:$GCS" \
  >/dev/null

  # SERIAL1 stays on TCP 5762 (+10 per instance): MAVProxy or a second GCS can connect there.
  echo "drone $name started with sysid $i, TCP port for telemetry: $((5762 + 10 * instance))"
done