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

DATA_DIR=$(mktemp -d "$REPOSITORY_ROOT/.docker-sh-run-smoke.XXXXXX")

remove_runtime_owned_directory() {
  local directory="$1"

  [ -e "$directory" ] || return 0
  if rm -rf -- "$directory" 2>/dev/null && [ ! -e "$directory" ]; then
    return 0
  fi
  if [ ! -d "$directory" ]; then
    echo "Runtime-test path is not a directory: $directory" >&2
    return 1
  fi

  # Delete files as the same container identity that created them. Numeric
  # host IDs must not be passed through Docker because rootless/userns daemons
  # would map those IDs a second time. The host can remove the empty bind root
  # using its permissions on DATA_DIR.
  if ! docker run --rm \
    --user 10001:10001 \
    --network none \
    --read-only \
    --security-opt no-new-privileges \
    --cap-drop ALL \
    --entrypoint find \
    --mount "type=bind,src=$directory,dst=/cleanup" \
    "$IMAGE" /cleanup -mindepth 1 -depth -delete; then
    echo "Failed to empty container-owned test directory: $directory" >&2
    return 1
  fi
  if ! rmdir -- "$directory"; then
    echo "Failed to remove empty test directory: $directory" >&2
    return 1
  fi
}

cleanup() {
  local test_status=$?
  local cleanup_status=0

  trap - EXIT
  set +e

  if ! bash "$DOCKER_SCRIPT" --rm --container-name "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Failed to remove smoke-test container: $CONTAINER_NAME" >&2
    cleanup_status=1
  fi

  if [ -d "$DATA_DIR" ]; then
    if ! remove_runtime_owned_directory "$DATA_DIR/output-directory"; then
      cleanup_status=1
    fi
    if ! remove_runtime_owned_directory "$DATA_DIR/logs"; then
      cleanup_status=1
    fi
    if ! rm -rf -- "$DATA_DIR"; then
      echo "Failed to remove smoke-test directory: $DATA_DIR" >&2
      cleanup_status=1
    fi
  fi

  if [ "$test_status" -eq 0 ] && [ "$cleanup_status" -ne 0 ]; then
    test_status=$cleanup_status
  fi
  exit "$test_status"
}
trap cleanup EXIT

run_node() (
  # Exercise the restrictive mode that previously made a second Linux run
  # unreadable to the invoking host user after ownership moved to UID 10001.
  umask 077
  bash "$DOCKER_SCRIPT" --run --image "$IMAGE" \
    --container-name "$CONTAINER_NAME" \
    --net private \
    --memory 2g \
    --jvm-opts "-Xms256m -XX:MaxRAMPercentage=40.0" \
    --data-dir "$DATA_DIR" \
    -- --p2p-disable true
)

dump_startup_diagnostics() {
  local diagnostic_jar="$DATA_DIR/framework-diagnostic.jar"
  local diagnostic_launcher="$DATA_DIR/FullNode-diagnostic"

  echo "FullNode startup diagnostics:" >&2
  docker inspect --format \
    'image={{.Image}} user={{.Config.User}} entrypoint={{json .Config.Entrypoint}} args={{json .Args}}' \
    "$CONTAINER_NAME" >&2 || true

  if docker cp "$CONTAINER_NAME:/java-tron/bin/FullNode" \
    "$diagnostic_launcher" >/dev/null 2>&1; then
    # Match the literal shell variables in the generated launcher.
    # shellcheck disable=SC2016
    grep -n -E '^(APP_HOME|CLASSPATH)=|exec "?\$JAVACMD|eval set --' \
      "$diagnostic_launcher" >&2 || true
  fi
  if docker cp "$CONTAINER_NAME:/java-tron/lib/framework-1.0.0.jar" \
    "$diagnostic_jar" >/dev/null 2>&1; then
    ls -l "$diagnostic_jar" >&2 || true
    if unzip -Z1 "$diagnostic_jar" | grep -Fxq \
      'org/tron/program/FullNode.class'; then
      echo "framework JAR contains org/tron/program/FullNode.class" >&2
    else
      echo "framework JAR is missing org/tron/program/FullNode.class" >&2
    fi
  else
    echo "Unable to copy framework-1.0.0.jar from the image" >&2
  fi

  echo "Traced launcher execution:" >&2
  timeout 10 docker run --rm \
    --network none \
    --entrypoint /bin/bash \
    --env 'JAVA_OPTS=-Xms256m -XX:MaxRAMPercentage=40.0' \
    "$IMAGE" -x ./bin/FullNode -c /java-tron/config.conf \
    --p2p-disable true >&2 || true
}

assert_node_stable() {
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
    dump_startup_diagnostics
    exit 1
  fi

  logs=$(docker logs "$CONTAINER_NAME" 2>&1 || true)
  if grep -Eiq 'Could not create the Java Virtual Machine|Unrecognized VM option|Error: Could not find or load main class' <<< "$logs"; then
    echo "FullNode failed to start:" >&2
    printf '%s\n' "$logs" >&2
    dump_startup_diagnostics
    exit 1
  fi
}

run_node
assert_node_stable
bash "$DOCKER_SCRIPT" --rm --container-name "$CONTAINER_NAME" >/dev/null

# Reuse the same private configuration, database and log directories. On a
# native Linux runner these paths are now owned by UID 10001 and remain 0700.
run_node
assert_node_stable

echo "docker.sh --run first-run and reuse smoke passed for $IMAGE"
