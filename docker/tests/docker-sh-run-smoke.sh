#!/bin/bash
# Short integration smoke: run docker.sh --run against a local image.
# Does not wait for RPC or chain sync.
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
REPOSITORY_ROOT=$(cd -- "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)
DOCKER_SCRIPT="$REPOSITORY_ROOT/docker/docker.sh"
CONTAINER_NAME="java-tron-smoke-$$-$RANDOM"
IMAGE="${1:-}"

if [ -z "$IMAGE" ]; then
  echo "Usage: $0 IMAGE" >&2
  exit 1
fi

DATA_DIR=$(mktemp -d)

cleanup() {
  bash "$DOCKER_SCRIPT" --rm --container-name "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

bash "$DOCKER_SCRIPT" --run --image "$IMAGE" \
  --container-name "$CONTAINER_NAME" \
  --net private \
  --memory 2g \
  --jvm-opts "-Xms256m -XX:MaxRAMPercentage=40.0" \
  --data-dir "$DATA_DIR" \
  -- --p2p-disable true

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != true ]; then
  echo "docker.sh --run did not leave a running container" >&2
  docker inspect "$CONTAINER_NAME" >&2 || true
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

sleep 12

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != true ]; then
  echo "The FullNode container exited during the smoke window" >&2
  docker inspect "$CONTAINER_NAME" >&2 || true
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

restarts=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER_NAME")
oom=$(docker inspect -f '{{.State.OOMKilled}}' "$CONTAINER_NAME")
if [ "$restarts" != 0 ] || [ "$oom" != false ]; then
  echo "The FullNode container restarted or was OOM-killed (restarts=$restarts oom=$oom)" >&2
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

logs=$(docker logs "$CONTAINER_NAME" 2>&1 || true)
if grep -Eiq 'Could not create the Java Virtual Machine|Unrecognized VM option|Error: Could not find or load main class' <<< "$logs"; then
  echo "FullNode failed to start:" >&2
  printf '%s\n' "$logs" >&2
  exit 1
fi

echo "docker.sh --run smoke passed for $IMAGE"
