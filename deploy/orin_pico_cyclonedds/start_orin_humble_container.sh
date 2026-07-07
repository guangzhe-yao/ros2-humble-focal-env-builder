#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${IMAGE:-10.51.33.201:30002/navi_project/sensor:22CUDA_humble}"
CONTAINER_NAME="${CONTAINER_NAME:-orin_humble_cyclone}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-20}"
CYCLONEDDS_CONFIG="${CYCLONEDDS_CONFIG:-$SCRIPT_DIR/orin-cyclonedds.xml}"
CYCLONEDDS_CONFIG_DIR="$(cd "$(dirname "$CYCLONEDDS_CONFIG")" && pwd)"
CYCLONEDDS_CONFIG_FILE="$(basename "$CYCLONEDDS_CONFIG")"
CONTAINER_CONFIG_DIR="/etc/ros/cyclonedds"
CONTAINER_CONFIG="$CONTAINER_CONFIG_DIR/$CYCLONEDDS_CONFIG_FILE"
COMMAND="${*:-sleep infinity}"

if [[ ! -f "$CYCLONEDDS_CONFIG" ]]; then
  echo "ERROR: CycloneDDS config not found: $CYCLONEDDS_CONFIG" >&2
  exit 1
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --network host \
  --ipc host \
  --entrypoint /bin/bash \
  -e ROS_DOMAIN_ID="$ROS_DOMAIN_ID" \
  -e ROS_LOCALHOST_ONLY=0 \
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI="file://$CONTAINER_CONFIG" \
  -v "$CYCLONEDDS_CONFIG_DIR:$CONTAINER_CONFIG_DIR:ro" \
  "$IMAGE" \
  -lc "source /opt/ros/humble/setup.bash && exec $COMMAND"

cat <<EOF
Started $CONTAINER_NAME
  image: $IMAGE
  ROS_DOMAIN_ID: $ROS_DOMAIN_ID
  RMW_IMPLEMENTATION: rmw_cyclonedds_cpp
  CYCLONEDDS_URI: file://$CONTAINER_CONFIG

Open a shell:
  docker exec -it $CONTAINER_NAME bash -lc 'source /opt/ros/humble/setup.bash && bash'
EOF
