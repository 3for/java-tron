#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
REPOSITORY_ROOT=$(cd -- "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)
DOCKER_SCRIPT="$REPOSITORY_ROOT/docker/docker.sh"
TEST_TMP=$(mktemp -d)
MOCK_BIN="$TEST_TMP/bin"
SOURCE_ROOT="$TEST_TMP/source"
DOCKER_LOG="$TEST_TMP/docker-args"
DOCKER_CONTEXT_LOG="$TEST_TMP/docker-context"
DOCKER_ENV_LOG="$TEST_TMP/docker-env"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$SOURCE_ROOT"
touch "$SOURCE_ROOT/.env"

cat > "$MOCK_BIN/docker" <<'MOCK_DOCKER'
#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "--version" ]; then
  echo "Docker version ${MOCK_DOCKER_VERSION:-23.0.0}, build mock"
  exit 0
fi

case "${1:-}" in
  build)
    printf '%s\n' "$@" > "$DOCKER_MOCK_LOG"
    printf '%s\n' "${DOCKER_BUILDKIT:-}" > "$DOCKER_MOCK_ENV_LOG"
    context="${!#}"
    (
      cd -- "$context"
      find . ! -type d -print | LC_ALL=C sort
    ) > "$DOCKER_MOCK_CONTEXT_LOG"
    ;;
  image)
    if [ "${2:-}" != "inspect" ]; then
      echo "Unexpected docker image command: $*" >&2
      exit 1
    fi
    ;;
  run)
    printf '%s\n' "$@" > "$DOCKER_MOCK_LOG"
    ;;
  *)
    echo "Unexpected docker command: $*" >&2
    exit 1
    ;;
esac
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

cat > "$MOCK_BIN/unzip" <<'MOCK_UNZIP'
#!/bin/bash
set -euo pipefail

destination=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-d" ]; then
    destination=$2
    shift 2
  else
    shift
  fi
done
test -n "$destination"
mkdir -p "$destination/java-tron-1.0.0/bin" "$destination/java-tron-1.0.0/lib"
touch "$destination/java-tron-1.0.0/bin/FullNode"
touch "$destination/java-tron-1.0.0/bin/java-tron.vmoptions"
touch "$destination/java-tron-1.0.0/lib/java-tron.jar"
chmod +x "$destination/java-tron-1.0.0/bin/FullNode"
MOCK_UNZIP

cat > "$MOCK_BIN/curl" <<'MOCK_CURL'
#!/bin/bash
set -euo pipefail

output=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    output=$2
    shift 2
  else
    shift
  fi
done
test -n "$output"
mkdir -p "$(dirname "$output")"
touch "$output"
MOCK_CURL

cat > "$SOURCE_ROOT/gradlew" <<'MOCK_GRADLEW'
#!/bin/bash
set -euo pipefail

mkdir -p framework/build/distributions
touch framework/build/distributions/java-tron-1.0.0.zip
MOCK_GRADLEW

chmod +x "$MOCK_BIN/docker" "$MOCK_BIN/uname" "$MOCK_BIN/unzip" \
  "$MOCK_BIN/curl" "$SOURCE_ROOT/gradlew"

assert_argument() {
  local expected="$1"
  if ! grep -Fqx -- "$expected" "$DOCKER_LOG"; then
    echo "Missing docker argument: $expected" >&2
    echo "Recorded arguments:" >&2
    sed 's/^/  /' "$DOCKER_LOG" >&2
    exit 1
  fi
}

assert_no_argument() {
  local unexpected="$1"
  if grep -Fqx -- "$unexpected" "$DOCKER_LOG"; then
    echo "Unexpected docker argument: $unexpected" >&2
    sed 's/^/  /' "$DOCKER_LOG" >&2
    exit 1
  fi
}

assert_context_file() {
  local expected="$1"
  if ! grep -Fqx -- "$expected" "$DOCKER_CONTEXT_LOG"; then
    echo "Missing Docker context file: $expected" >&2
    sed 's/^/  /' "$DOCKER_CONTEXT_LOG" >&2
    exit 1
  fi
}

assert_context_only_dockerfile() {
  if [ "$(cat "$DOCKER_CONTEXT_LOG")" != "./Dockerfile" ]; then
    echo "Remote build context contains unexpected files:" >&2
    sed 's/^/  /' "$DOCKER_CONTEXT_LOG" >&2
    exit 1
  fi
}

assert_temporary_context() {
  local actual
  actual=$(tail -n 1 "$DOCKER_LOG")
  if [ "$actual" = "$REPOSITORY_ROOT" ] || [ "$actual" = "$REPOSITORY_ROOT/docker" ]; then
    echo "Docker build used a repository directory as its context: $actual" >&2
    exit 1
  fi
}

assert_buildkit_enabled() {
  if [ "$(cat "$DOCKER_ENV_LOG")" != "1" ]; then
    echo "docker.sh did not enable BuildKit" >&2
    exit 1
  fi
}

run_build() {
  local architecture="$1"
  local working_directory="$2"
  shift 2
  : > "$DOCKER_LOG"
  : > "$DOCKER_CONTEXT_LOG"
  : > "$DOCKER_ENV_LOG"
  (
    cd -- "$working_directory"
    PATH="$MOCK_BIN:$PATH" \
      MOCK_ARCH="$architecture" \
      DOCKER_MOCK_LOG="$DOCKER_LOG" \
      DOCKER_MOCK_CONTEXT_LOG="$DOCKER_CONTEXT_LOG" \
      DOCKER_MOCK_ENV_LOG="$DOCKER_ENV_LOG" \
      bash "$DOCKER_SCRIPT" --build "$@"
  )
}

run_node() {
  : > "$DOCKER_LOG"
  (
    cd -- "$TEST_TMP"
    PATH="$MOCK_BIN:$PATH" \
      DOCKER_MOCK_LOG="$DOCKER_LOG" \
      DOCKER_MOCK_CONTEXT_LOG="$DOCKER_CONTEXT_LOG" \
      DOCKER_MOCK_ENV_LOG="$DOCKER_ENV_LOG" \
      bash "$DOCKER_SCRIPT" --run -c /java-tron/test.conf "$@"
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
      DOCKER_MOCK_CONTEXT_LOG="$DOCKER_CONTEXT_LOG" \
      DOCKER_MOCK_ENV_LOG="$DOCKER_ENV_LOG" \
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
assert_argument "--target"
assert_argument "remote"
assert_argument "SOURCE_REPOSITORY=https://github.com/tronprotocol/java-tron.git"
assert_argument "SOURCE_REF=master"
assert_no_argument "SOURCE_MODE=remote"
assert_temporary_context
assert_context_only_dockerfile
assert_buildkit_enabled
if [[ "$remote_output" != *"Local working-tree changes are not included"* ]]; then
  echo "The backward-compatible remote build notice is missing." >&2
  exit 1
fi

run_build x86_64 "$SOURCE_ROOT" --source local >/dev/null
assert_argument "--target"
assert_argument "local"
assert_no_argument "SOURCE_MODE=local"
assert_temporary_context
assert_context_file "./Dockerfile"
assert_context_file "./java-tron/bin/FullNode"
assert_context_file "./java-tron/bin/java-tron.vmoptions"
assert_context_file "./java-tron/config.conf"
assert_context_file "./java-tron/lib/java-tron.jar"
if grep -Fqx -- "./.env" "$DOCKER_CONTEXT_LOG"; then
  echo "The local source .env file leaked into the Docker build context." >&2
  exit 1
fi
assert_buildkit_enabled

run_build x86_64 "$REPOSITORY_ROOT" \
  --source remote \
  --source-ref develop \
  --source-repository https://example.com/java-tron.git >/dev/null
assert_argument "remote"
assert_argument "SOURCE_REPOSITORY=https://example.com/java-tron.git"
assert_argument "SOURCE_REF=develop"
assert_context_only_dockerfile

run_build aarch64 "$SOURCE_ROOT" --source local >/dev/null
assert_argument "local"
assert_context_file "./Dockerfile"
assert_context_file "./java-tron/bin/FullNode"

expect_failure "requires a value" --source
expect_failure "expected local or remote" --source invalid
expect_failure "can only be used with --source remote" --source local --source-ref develop
expect_failure "is not a valid parameter" --unknown

if output=$(
  cd -- "$REPOSITORY_ROOT"
  PATH="$MOCK_BIN:$PATH" MOCK_DOCKER_VERSION=22.0.0 \
    bash "$DOCKER_SCRIPT" --build 2>&1
); then
  echo "Expected Docker 22 to be rejected" >&2
  exit 1
fi
if [[ "$output" != *"Docker 23.0 or later is required"* ]]; then
  echo "The Docker minimum-version failure is unclear:" >&2
  echo "$output" >&2
  exit 1
fi

run_node >/dev/null
assert_argument "127.0.0.1:8090:8090"
assert_argument "127.0.0.1:50051:50051"
assert_argument "18888:18888"
assert_argument "18888:18888/udp"
assert_no_argument "8090:8090"
assert_no_argument "50051:50051"

run_node -p 8090:8090 -p 50051:50051 >/dev/null
assert_argument "8090:8090"
assert_argument "50051:50051"
assert_no_argument "127.0.0.1:8090:8090"
assert_no_argument "127.0.0.1:50051:50051"

echo "docker.sh build and run tests passed"
