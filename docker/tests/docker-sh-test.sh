#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
REPOSITORY_ROOT=$(cd -- "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)
DOCKER_SCRIPT="$REPOSITORY_ROOT/docker/docker.sh"
TEST_TMP=$(mktemp -d)
MOCK_BIN="$TEST_TMP/bin"
SOURCE_ROOT="$TEST_TMP/source"
SOURCE_WITHOUT_DOCKERFILE="$TEST_TMP/source-without-dockerfile"
STANDALONE_DIR="$TEST_TMP/standalone"
DOCKER_LOG="$TEST_TMP/docker-args"
DOCKER_CONTEXT_LOG="$TEST_TMP/docker-context"
DOCKER_ENV_LOG="$TEST_TMP/docker-env"
DOWNLOAD_LOG="$TEST_TMP/downloads"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$SOURCE_ROOT/docker/arm64" "$TEST_TMP/config" \
  "$SOURCE_WITHOUT_DOCKERFILE" \
  "$TEST_TMP/external-data/config" "$TEST_TMP/relative-data/config"
cp "$REPOSITORY_ROOT/docker/Dockerfile" "$SOURCE_ROOT/docker/Dockerfile"
cp "$REPOSITORY_ROOT/docker/arm64/Dockerfile" "$SOURCE_ROOT/docker/arm64/Dockerfile"
touch "$SOURCE_ROOT/.env"
printf 'seed-config\n' > "$TEST_TMP/config/main_net_config.conf"
printf 'seed-config\n' > "$TEST_TMP/config/test_net_config.conf"
printf 'seed-config\n' > "$TEST_TMP/external-data/config/main_net_config.conf"
printf 'seed-config\n' > "$TEST_TMP/relative-data/config/main_net_config.conf"

cat > "$MOCK_BIN/docker" <<'MOCK_DOCKER'
#!/bin/bash
set -euo pipefail

if [ "${MOCK_DOCKER_FORBIDDEN:-false}" = true ]; then
  echo "docker must not be called for help" >&2
  exit 97
fi

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
    if [ "${3:-}" = "-f" ]; then
      echo "${MOCK_IMAGE_ARCH:-amd64}"
    fi
    ;;
  ps)
    if [ "${2:-}" != "-aq" ]; then
      echo "Unexpected docker ps command: $*" >&2
      exit 1
    fi
    if [ "${MOCK_CONTAINER_EXISTS:-false}" = true ]; then
      echo "deadbeef"
    fi
    ;;
  run)
    printf '%s\n' "$@" > "$DOCKER_MOCK_LOG"
    exit "${MOCK_RUN_STATUS:-0}"
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
url=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    output=$2
    shift 2
  else
    if [[ "$1" != -* ]]; then
      url=$1
    fi
    shift
  fi
done
test -n "$output"
mkdir -p "$(dirname "$output")"
if [ -n "${DOWNLOAD_MOCK_LOG:-}" ]; then
  printf '%s|%s\n' "$url" "$output" >> "$DOWNLOAD_MOCK_LOG"
fi
if [ "${MOCK_CURL_FAIL:-false}" = true ]; then
  printf 'partial-download\n' > "$output"
  exit 1
fi
if [ "${MOCK_CURL_EMPTY:-false}" = true ]; then
  : > "$output"
  exit 0
fi
printf 'downloaded-content\n' > "$output"
MOCK_CURL

cat > "$SOURCE_ROOT/gradlew" <<'MOCK_GRADLEW'
#!/bin/bash
set -euo pipefail

mkdir -p framework/build/distributions
touch framework/build/distributions/java-tron-1.0.0.zip
MOCK_GRADLEW

chmod +x "$MOCK_BIN/docker" "$MOCK_BIN/uname" "$MOCK_BIN/unzip" \
  "$MOCK_BIN/curl" "$SOURCE_ROOT/gradlew"
cp "$SOURCE_ROOT/gradlew" "$SOURCE_WITHOUT_DOCKERFILE/gradlew"

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

assert_argument_count() {
  local expected="$1"
  local count="$2"
  local actual
  actual=$(grep -Fxc -- "$expected" "$DOCKER_LOG" || true)
  if [ "$actual" -ne "$count" ]; then
    echo "Expected docker argument '$expected' $count times, got $actual" >&2
    sed 's/^/  /' "$DOCKER_LOG" >&2
    exit 1
  fi
}

assert_trailing_arguments() {
  local expected
  local actual
  expected=$(printf '%s\n' "$@")
  actual=$(tail -n "$#" "$DOCKER_LOG")
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected trailing docker arguments:" >&2
    echo "Expected:" >&2
    printf '  %s\n' "$@" >&2
    echo "Actual:" >&2
    printf '%s\n' "$actual" | sed 's/^/  /' >&2
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

run_standalone_build() {
  local architecture="$1"
  local working_directory="$2"
  shift 2
  mkdir -p "$STANDALONE_DIR"
  cp "$DOCKER_SCRIPT" "$STANDALONE_DIR/docker.sh"
  : > "$DOCKER_LOG"
  : > "$DOCKER_CONTEXT_LOG"
  : > "$DOCKER_ENV_LOG"
  : > "$DOWNLOAD_LOG"
  (
    cd -- "$working_directory"
    PATH="$MOCK_BIN:$PATH" \
      MOCK_ARCH="$architecture" \
      DOCKER_MOCK_LOG="$DOCKER_LOG" \
      DOCKER_MOCK_CONTEXT_LOG="$DOCKER_CONTEXT_LOG" \
      DOCKER_MOCK_ENV_LOG="$DOCKER_ENV_LOG" \
      DOWNLOAD_MOCK_LOG="$DOWNLOAD_LOG" \
      MOCK_CURL_FAIL="${MOCK_CURL_FAIL:-false}" \
      MOCK_CURL_EMPTY="${MOCK_CURL_EMPTY:-false}" \
      bash "$STANDALONE_DIR/docker.sh" --build "$@"
  )
}

run_node() {
  : > "$DOCKER_LOG"
  : > "$DOWNLOAD_LOG"
  (
    cd -- "$TEST_TMP"
    PATH="$MOCK_BIN:$PATH" \
      DOCKER_MOCK_LOG="$DOCKER_LOG" \
      DOCKER_MOCK_CONTEXT_LOG="$DOCKER_CONTEXT_LOG" \
      DOCKER_MOCK_ENV_LOG="$DOCKER_ENV_LOG" \
      DOWNLOAD_MOCK_LOG="$DOWNLOAD_LOG" \
      MOCK_RUN_STATUS="${MOCK_RUN_STATUS:-0}" \
      MOCK_CONTAINER_EXISTS="${MOCK_CONTAINER_EXISTS:-false}" \
      MOCK_IMAGE_ARCH="${MOCK_IMAGE_ARCH:-amd64}" \
      MOCK_CURL_FAIL="${MOCK_CURL_FAIL:-false}" \
      MOCK_CURL_EMPTY="${MOCK_CURL_EMPTY:-false}" \
      bash "$DOCKER_SCRIPT" --run "$@"
  )
}

expect_run_failure() {
  local expected_message="$1"
  shift
  local output

  if output=$(run_node "$@" 2>&1); then
    echo "Expected command to fail: --run $*" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_message"* ]]; then
    echo "Expected run failure message '$expected_message', got:" >&2
    echo "$output" >&2
    exit 1
  fi
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

help_output=$(
  PATH="$MOCK_BIN:$PATH" MOCK_DOCKER_FORBIDDEN=true \
    bash "$DOCKER_SCRIPT" --help
)
if [[ "$help_output" != *"Usage: docker.sh COMMAND [OPTIONS]"* ]]; then
  echo "--help did not print usage" >&2
  exit 1
fi

set +e
no_arg_output=$(
  PATH="$MOCK_BIN:$PATH" MOCK_DOCKER_FORBIDDEN=true \
    bash "$DOCKER_SCRIPT" 2>&1
)
no_arg_status=$?
set -e
if [ "$no_arg_status" -ne 1 ] || [[ "$no_arg_output" != *"Usage: docker.sh COMMAND [OPTIONS]"* ]]; then
  echo "Invoking docker.sh without arguments did not return usage and status 1" >&2
  exit 1
fi

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

run_standalone_build x86_64 "$TEST_TMP" >/dev/null
if ! grep -Fq -- \
  "https://raw.githubusercontent.com/tronprotocol/java-tron/master/docker/Dockerfile|$STANDALONE_DIR/Dockerfile.tmp." \
  "$DOWNLOAD_LOG"; then
  echo "The standalone build did not download its Dockerfile from master" >&2
  sed 's/^/  /' "$DOWNLOAD_LOG" >&2
  exit 1
fi
if [ ! -s "$STANDALONE_DIR/Dockerfile" ]; then
  echo "The standalone build did not replace the Dockerfile atomically" >&2
  exit 1
fi
if compgen -G "$STANDALONE_DIR/Dockerfile.tmp.*" >/dev/null; then
  echo "The standalone build left a temporary Dockerfile behind" >&2
  exit 1
fi
assert_argument "SOURCE_REF=master"
assert_context_only_dockerfile
assert_buildkit_enabled

rm -f "$STANDALONE_DIR/Dockerfile"
if MOCK_CURL_FAIL=true run_standalone_build x86_64 "$TEST_TMP" >/dev/null 2>&1; then
  echo "A failed Dockerfile download unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$STANDALONE_DIR/Dockerfile" ]; then
  echo "A failed Dockerfile download left a destination file" >&2
  exit 1
fi
if compgen -G "$STANDALONE_DIR/Dockerfile.tmp.*" >/dev/null; then
  echo "A failed Dockerfile download left a temporary file" >&2
  exit 1
fi

rm -f "$STANDALONE_DIR/Dockerfile"
run_standalone_build x86_64 "$SOURCE_ROOT" --source local >/dev/null
if grep -Fq -- "/tronprotocol/java-tron/master/docker/Dockerfile" "$DOWNLOAD_LOG"; then
  echo "The standalone local build downloaded a Dockerfile instead of using the checkout" >&2
  sed 's/^/  /' "$DOWNLOAD_LOG" >&2
  exit 1
fi
assert_argument "--target"
assert_argument "local"
assert_context_file "./Dockerfile"
assert_context_file "./java-tron/bin/FullNode"
assert_buildkit_enabled

if missing_dockerfile_output=$(run_standalone_build \
  x86_64 "$SOURCE_WITHOUT_DOCKERFILE" --source local 2>&1); then
  echo "A local build without a checkout Dockerfile unexpectedly succeeded" >&2
  exit 1
fi
if [[ "$missing_dockerfile_output" != *"local Dockerfile does not exist"* ]]; then
  echo "The missing local Dockerfile failure was unclear:" >&2
  echo "$missing_dockerfile_output" >&2
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
assert_argument "-d"
assert_no_argument "-it"
assert_argument "127.0.0.1:8090:8090"
assert_argument "127.0.0.1:50051:50051"
assert_argument "18888:18888"
assert_argument "18888:18888/udp"
assert_no_argument "8090:8090"
assert_no_argument "50051:50051"
assert_argument "16g"
assert_argument "JAVA_OPTS=-Xms2g -XX:MaxRAMPercentage=60.0 -XX:MaxDirectMemorySize=1g"
assert_argument "$TEST_TMP/config:/java-tron/config"
assert_argument "$TEST_TMP/output-directory:/java-tron/output-directory"
assert_argument "$TEST_TMP/logs:/java-tron/logs"
assert_argument "/java-tron/config/main_net_config.conf"
assert_argument "tronprotocol/java-tron:latest"
assert_argument_count "-p" 4
assert_argument_count "-v" 3
assert_argument_count "--env" 1
if [ -s "$DOWNLOAD_LOG" ]; then
  echo "--update-config false unexpectedly downloaded an existing configuration" >&2
  exit 1
fi

MOCK_IMAGE_ARCH=arm64 run_node >/dev/null
assert_argument "JAVA_OPTS=-Xms2g -XX:MaxRAMPercentage=60.0"
assert_no_argument "JAVA_OPTS=-Xms2g -XX:MaxRAMPercentage=60.0 -XX:MaxDirectMemorySize=1g"
MOCK_IMAGE_ARCH=amd64

run_node --data-dir "$TEST_TMP/external-data" >/dev/null
assert_argument "$TEST_TMP/external-data/config:/java-tron/config"
assert_argument "$TEST_TMP/external-data/output-directory:/java-tron/output-directory"
assert_argument "$TEST_TMP/external-data/logs:/java-tron/logs"
assert_no_argument "$TEST_TMP/config:/java-tron/config"
assert_no_argument "$TEST_TMP/output-directory:/java-tron/output-directory"

run_node --data-dir relative-data >/dev/null
assert_argument "$TEST_TMP/relative-data/config:/java-tron/config"
assert_argument "$TEST_TMP/relative-data/output-directory:/java-tron/output-directory"
assert_argument "$TEST_TMP/relative-data/logs:/java-tron/logs"

run_node -c /java-tron/custom.conf \
  -p 8090:8090 \
  -p 50051:50051 \
  -p 28888:18888 \
  -v /host/config.conf:/java-tron/config:ro \
  -v /host/logs:/java-tron/logs \
  -v /host/extra:/extra:ro \
  -e TZ=UTC \
  --env FEATURE_FLAG=enabled \
  --memory 32g \
  --jvm-opts "-Xms4g -Xmx18g -XX:MaxDirectMemorySize=2g" \
  -- --p2p-disable false --log-config "/java-tron/log configs/logback.xml" >/dev/null
assert_argument "8090:8090"
assert_argument "50051:50051"
assert_argument "28888:18888"
assert_argument "18888:18888/udp"
assert_no_argument "127.0.0.1:8090:8090"
assert_no_argument "127.0.0.1:50051:50051"
assert_no_argument "18888:18888"
assert_argument "/host/config.conf:/java-tron/config:ro"
assert_argument "/host/logs:/java-tron/logs"
assert_argument "/host/extra:/extra:ro"
assert_no_argument "$TEST_TMP/config:/java-tron/config"
assert_no_argument "$TEST_TMP/logs:/java-tron/logs"
assert_argument "$TEST_TMP/output-directory:/java-tron/output-directory"
assert_argument "TZ=UTC"
assert_argument "FEATURE_FLAG=enabled"
assert_argument "32g"
assert_argument "JAVA_OPTS=-Xms4g -Xmx18g -XX:MaxDirectMemorySize=2g"
assert_argument "/java-tron/custom.conf"
assert_trailing_arguments \
  "tronprotocol/java-tron:latest" \
  "-c" \
  "/java-tron/custom.conf" \
  "--p2p-disable" \
  "false" \
  "--log-config" \
  "/java-tron/log configs/logback.xml"
assert_argument_count "-p" 4
assert_argument_count "-v" 4
assert_argument_count "--env" 3
if [ -s "$DOWNLOAD_LOG" ]; then
  echo "A custom configuration unexpectedly triggered a download" >&2
  exit 1
fi

run_node --net test --update-config false >/dev/null
assert_argument "/java-tron/config/test_net_config.conf"

run_node --net private --update-config false >/dev/null
assert_argument "/java-tron/config/private_net_config.conf"
if ! grep -Fq -- \
  "https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/private_net_config.conf|$TEST_TMP/config/private_net_config.conf.tmp." \
  "$DOWNLOAD_LOG"; then
  echo "--update-config false did not download a missing configuration" >&2
  sed 's/^/  /' "$DOWNLOAD_LOG" >&2
  exit 1
fi
if [ "$(cat "$TEST_TMP/config/private_net_config.conf")" != "downloaded-content" ]; then
  echo "The missing configuration was not written to the destination" >&2
  exit 1
fi

run_node --net main --update-config true >/dev/null
if ! grep -Fq -- \
  "https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/main_net_config.conf|$TEST_TMP/config/main_net_config.conf.tmp." \
  "$DOWNLOAD_LOG"; then
  echo "--update-config true did not refresh the selected configuration" >&2
  sed 's/^/  /' "$DOWNLOAD_LOG" >&2
  exit 1
fi
if [ "$(cat "$TEST_TMP/config/main_net_config.conf")" != "downloaded-content" ]; then
  echo "--update-config true did not replace the configuration atomically" >&2
  exit 1
fi

printf 'valid-config\n' > "$TEST_TMP/config/main_net_config.conf"
if MOCK_CURL_FAIL=true run_node --net main --update-config true >/dev/null 2>&1; then
  echo "A failed configuration refresh unexpectedly succeeded" >&2
  exit 1
fi
if [ "$(cat "$TEST_TMP/config/main_net_config.conf")" != "valid-config" ]; then
  echo "A failed refresh corrupted the existing configuration" >&2
  cat "$TEST_TMP/config/main_net_config.conf" >&2
  exit 1
fi
if compgen -G "$TEST_TMP/config/main_net_config.conf.tmp.*" >/dev/null; then
  echo "A failed refresh left a temporary configuration file" >&2
  exit 1
fi

CONFIG_FILE_FOR_TEST="$TEST_TMP/config/private_net_config.conf"
rm -f "$CONFIG_FILE_FOR_TEST"
if MOCK_CURL_FAIL=true run_node --net private --update-config false >/dev/null 2>&1; then
  echo "A failed initial configuration download unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$CONFIG_FILE_FOR_TEST" ]; then
  echo "A failed initial download left a destination configuration file" >&2
  exit 1
fi
if compgen -G "$CONFIG_FILE_FOR_TEST.tmp.*" >/dev/null; then
  echo "A failed initial download left a temporary configuration file" >&2
  exit 1
fi

: > "$TEST_TMP/config/test_net_config.conf"
run_node --net test --update-config false >/dev/null
if [ "$(cat "$TEST_TMP/config/test_net_config.conf")" != "downloaded-content" ]; then
  echo "An empty configuration was treated as valid and not replaced" >&2
  exit 1
fi

printf 'valid-config\n' > "$TEST_TMP/config/main_net_config.conf"
if MOCK_CURL_EMPTY=true run_node --net main --update-config true >/dev/null 2>&1; then
  echo "An empty downloaded configuration unexpectedly succeeded" >&2
  exit 1
fi
if [ "$(cat "$TEST_TMP/config/main_net_config.conf")" != "valid-config" ]; then
  echo "An empty download replaced the existing configuration" >&2
  cat "$TEST_TMP/config/main_net_config.conf" >&2
  exit 1
fi
if compgen -G "$TEST_TMP/config/main_net_config.conf.tmp.*" >/dev/null; then
  echo "An empty download left a temporary configuration file" >&2
  exit 1
fi

for option in -v -p -e --env -c --net --update-config --memory --jvm-opts --data-dir; do
  expect_run_failure "requires a value" "$option"
done
expect_run_failure "expected main, test, or private" --net unsupported
expect_run_failure "must be true or false" --update-config sometimes
expect_run_failure "is not a valid parameter" --unknown
expect_run_failure "use --jvm-opts to set JVM options" -e "JAVA_OPTS=-Xmx8g"
expect_run_failure "use --jvm-opts to set JVM options" --env "FULL_NODE_OPTS=-Xmx8g"

run_node -c /java-tron/custom.conf -- --unknown-fullnode-option >/dev/null
assert_trailing_arguments \
  "tronprotocol/java-tron:latest" \
  "-c" \
  "/java-tron/custom.conf" \
  "--unknown-fullnode-option"

set +e
duplicate_output=$(MOCK_CONTAINER_EXISTS=true run_node -c /java-tron/custom.conf 2>&1)
duplicate_status=$?
set -e
if [ "$duplicate_status" -ne 1 ] \
  || [[ "$duplicate_output" != *"already exists"* ]] \
  || [[ "$duplicate_output" != *"Use --start"* ]]; then
  echo "An existing container did not produce an actionable error" >&2
  echo "$duplicate_output" >&2
  exit 1
fi
if [ -s "$DOCKER_LOG" ]; then
  echo "docker run was called even though the container already exists" >&2
  exit 1
fi

set +e
MOCK_RUN_STATUS=47 run_node -c /java-tron/custom.conf >/dev/null 2>&1
run_status=$?
set -e
if [ "$run_status" -ne 47 ]; then
  echo "Expected docker run failure status 47, got $run_status" >&2
  exit 1
fi

echo "docker.sh build and run tests passed"
