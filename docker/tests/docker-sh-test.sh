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

if [ "${1:-}" = "--version" ]; then
  echo "Docker version mock"
  exit 0
fi

if [ "${1:-}" != "build" ]; then
  echo "Unexpected docker command: $*" >&2
  exit 1
fi

printf '%s\n' "$@" > "$DOCKER_MOCK_LOG"
MOCK_DOCKER

cat > "$MOCK_BIN/uname" <<'MOCK_UNAME'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "-m" ]; then
  echo "${MOCK_ARCH:-x86_64}"
  exit 0
fi

exec /usr/bin/uname "$@"
MOCK_UNAME

chmod +x "$MOCK_BIN/docker" "$MOCK_BIN/uname"

assert_argument() {
  local expected="$1"
  if ! grep -Fqx -- "$expected" "$DOCKER_LOG"; then
    echo "Missing docker argument: $expected" >&2
    echo "Recorded arguments:" >&2
    sed 's/^/  /' "$DOCKER_LOG" >&2
    exit 1
  fi
}

assert_context() {
  local expected="$1"
  local actual
  actual=$(tail -n 1 "$DOCKER_LOG")
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected Docker build context: expected $expected, got $actual" >&2
    exit 1
  fi
}

run_build() {
  local architecture="$1"
  local working_directory="$2"
  shift 2
  : > "$DOCKER_LOG"
  (
    cd -- "$working_directory"
    PATH="$MOCK_BIN:$PATH" \
      MOCK_ARCH="$architecture" \
      DOCKER_MOCK_LOG="$DOCKER_LOG" \
      bash "$DOCKER_SCRIPT" --build "$@"
  )
}

expect_failure() {
  local expected_message="$1"
  shift
  local output
  if output=$(
    cd -- "$REPOSITORY_ROOT"
    PATH="$MOCK_BIN:$PATH" \
      MOCK_ARCH=x86_64 \
      DOCKER_MOCK_LOG="$DOCKER_LOG" \
      bash "$DOCKER_SCRIPT" --build "$@" 2>&1
  ); then
    echo "Expected command to fail: --build $*" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    echo "Expected failure message '$expected_message', got:" >&2
    echo "$output" >&2
    exit 1
  fi
}

remote_output=$(run_build x86_64 "$REPOSITORY_ROOT")
assert_argument "$REPOSITORY_ROOT/docker/Dockerfile"
assert_argument "SOURCE_MODE=remote"
assert_argument "SOURCE_REPOSITORY=https://github.com/tronprotocol/java-tron.git"
assert_argument "SOURCE_REF=master"
assert_context "$REPOSITORY_ROOT/docker"
if [[ "$remote_output" != *"Local working-tree changes are not included"* ]]; then
  echo "The backward-compatible remote build notice is missing." >&2
  exit 1
fi

run_build x86_64 "$REPOSITORY_ROOT" --source local >/dev/null
assert_argument "$REPOSITORY_ROOT/docker/Dockerfile"
assert_argument "SOURCE_MODE=local"
assert_context "$REPOSITORY_ROOT"

run_build x86_64 "$REPOSITORY_ROOT" \
  --source remote \
  --source-ref develop \
  --source-repository https://example.com/java-tron.git >/dev/null
assert_argument "SOURCE_MODE=remote"
assert_argument "SOURCE_REPOSITORY=https://example.com/java-tron.git"
assert_argument "SOURCE_REF=develop"
assert_context "$REPOSITORY_ROOT/docker"

run_build aarch64 "$REPOSITORY_ROOT/docker" --source local >/dev/null
assert_argument "$REPOSITORY_ROOT/docker/arm64/Dockerfile"
assert_argument "SOURCE_MODE=local"
assert_context "$REPOSITORY_ROOT"

expect_failure "requires a value" --source
expect_failure "expected local or remote" --source invalid
expect_failure "can only be used with --source remote" --source local --source-ref develop
expect_failure "is not a valid parameter" --unknown

echo "docker.sh build tests passed"
