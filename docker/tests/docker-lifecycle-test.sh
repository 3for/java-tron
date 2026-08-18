#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
REPOSITORY_ROOT=$(cd -- "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)
DOCKER_SCRIPT="$REPOSITORY_ROOT/docker/docker.sh"
TEST_TMP=$(mktemp -d)
MOCK_BIN="$TEST_TMP/bin"
DOCKER_LOG="$TEST_TMP/docker-args"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/docker" <<'MOCK_DOCKER'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "$DOCKER_MOCK_LOG"

case "${1:-}" in
  --version)
    echo "Docker version 23.0.0, build mock"
    ;;
  ps)
    if [ "${2:-}" = "-aq" ]; then
      if [ "${MOCK_QUERY_STATUS:-0}" -ne 0 ]; then
        exit "$MOCK_QUERY_STATUS"
      fi
      if [ "${MOCK_CONTAINER_EXISTS:-false}" = true ]; then
        echo "deadbeef"
      fi
    else
      exit "${MOCK_PS_STATUS:-0}"
    fi
    ;;
  start)
    exit "${MOCK_START_STATUS:-0}"
    ;;
  stop)
    exit "${MOCK_STOP_STATUS:-0}"
    ;;
  rm)
    exit "${MOCK_RM_STATUS:-0}"
    ;;
  exec)
    exit "${MOCK_EXEC_STATUS:-0}"
    ;;
  *)
    echo "Unexpected docker command: $*" >&2
    exit 99
    ;;
esac
MOCK_DOCKER

chmod +x "$MOCK_BIN/docker"

run_lifecycle() {
  local operation="$1"
  shift

  : > "$DOCKER_LOG"
  env \
    PATH="$MOCK_BIN:$PATH" \
    DOCKER_MOCK_LOG="$DOCKER_LOG" \
    "$@" \
    bash "$DOCKER_SCRIPT" "$operation"
}

expect_status() {
  local expected="$1"
  shift
  local actual

  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e

  if [ "$actual" -ne "$expected" ]; then
    echo "Expected exit status $expected, got $actual: $*" >&2
    sed 's/^/  docker /' "$DOCKER_LOG" >&2
    exit 1
  fi
}

assert_call_count() {
  local pattern="$1"
  local expected="$2"
  local actual

  actual=$(grep -Ec -- "$pattern" "$DOCKER_LOG" || true)
  if [ "$actual" -ne "$expected" ]; then
    echo "Expected $expected calls matching '$pattern', got $actual" >&2
    sed 's/^/  docker /' "$DOCKER_LOG" >&2
    exit 1
  fi
}

expect_status 1 run_lifecycle --start \
  MOCK_CONTAINER_EXISTS=true MOCK_START_STATUS=42
assert_call_count '^ps -aq ' 1
assert_call_count '^ps$' 0

expect_status 1 run_lifecycle --stop \
  MOCK_CONTAINER_EXISTS=true MOCK_STOP_STATUS=43
assert_call_count '^ps -aq ' 1
assert_call_count '^ps$' 0

expect_status 1 run_lifecycle --start MOCK_CONTAINER_EXISTS=false
expect_status 1 run_lifecycle --stop MOCK_CONTAINER_EXISTS=false
expect_status 1 run_lifecycle --log MOCK_CONTAINER_EXISTS=false

expect_status 1 run_lifecycle --start MOCK_QUERY_STATUS=51
assert_call_count '^start ' 0

expect_status 1 run_lifecycle --start \
  MOCK_CONTAINER_EXISTS=true MOCK_PS_STATUS=52
expect_status 1 run_lifecycle --stop \
  MOCK_CONTAINER_EXISTS=true MOCK_PS_STATUS=53

expect_status 1 run_lifecycle --log \
  MOCK_CONTAINER_EXISTS=true MOCK_EXEC_STATUS=44

expect_status 1 run_lifecycle --rm \
  MOCK_CONTAINER_EXISTS=true MOCK_RM_STATUS=45
expect_status 1 run_lifecycle --rm MOCK_CONTAINER_EXISTS=false

expect_status 0 run_lifecycle --start MOCK_CONTAINER_EXISTS=true
assert_call_count '^start deadbeef$' 1
assert_call_count '^ps$' 1

expect_status 0 run_lifecycle --stop MOCK_CONTAINER_EXISTS=true
assert_call_count '^stop deadbeef$' 1
assert_call_count '^ps$' 1

expect_status 0 run_lifecycle --log MOCK_CONTAINER_EXISTS=true
assert_call_count '^exec -it deadbeef tail -100f /java-tron/logs/tron.log$' 1

expect_status 0 run_lifecycle --rm MOCK_CONTAINER_EXISTS=true
assert_call_count '^stop deadbeef$' 1
assert_call_count '^rm deadbeef$' 1

echo "docker.sh lifecycle tests passed"
