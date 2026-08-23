#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
REPOSITORY_ROOT=$(cd -- "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)
START_SCRIPT="$REPOSITORY_ROOT/start.sh"
TEST_TMP=$(mktemp -d)
DOWNLOAD_LOG="$TEST_TMP/downloads"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

function_source=$(awk '
  /^(downloadTo\(\) \{|quickStart\(\) \{|specifyConfig\(\)\{)$/ { capture = 1 }
  capture { print }
  capture && /^}$/ { capture = 0 }
' "$START_SCRIPT")
eval "$function_source"

if ! declare -F specifyConfig >/dev/null ||
   ! declare -F downloadTo >/dev/null ||
   ! declare -F quickStart >/dev/null; then
  echo "Failed to load the configuration functions from start.sh" >&2
  exit 1
fi

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$actual" != "$expected" ]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_no_download_temps() {
  local directory="$1"
  local output_name="$2"
  local leftover

  leftover=$(find "$directory" -maxdepth 1 -name ".${output_name}.tmp.*" -print -quit)
  if [[ -n "$leftover" ]]; then
    echo "Temporary download file was not cleaned up: $leftover" >&2
    exit 1
  fi
}

# Exercise the real downloadTo implementation through a deterministic wget
# fixture before replacing it with the smaller specifyConfig test double.
download_bin="$TEST_TMP/download-bin"
mkdir -p "$download_bin"
cat > "$download_bin/wget" <<'MOCK_WGET'
#!/bin/bash
set -euo pipefail

output=''
url=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -O)
      output=$2
      shift 2
      ;;
    -q)
      shift
      ;;
    --no-check-certificate)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

if [[ -z "$output" ]]; then
  output=${url##*/}
fi

printf '%s|%s\n' "$url" "$output" >> "$MOCK_DOWNLOAD_LOG"
case "$MOCK_DOWNLOAD_MODE" in
  success)
    printf 'downloaded from %s\n' "$url" > "$output"
    ;;
  empty)
    : > "$output"
    ;;
  fail)
    printf 'partial download\n' > "$output"
    exit 23
    ;;
  *)
    echo "Unexpected download fixture mode: $MOCK_DOWNLOAD_MODE" >&2
    exit 64
    ;;
esac
MOCK_WGET
chmod +x "$download_bin/wget"

atomic_root="$TEST_TMP/atomic-download"
mkdir -p "$atomic_root"
atomic_config="$atomic_root/config.conf"
MOCK_DOWNLOAD_LOG="$TEST_TMP/atomic-downloads"
export MOCK_DOWNLOAD_LOG
PATH="$download_bin:$PATH"
export PATH

printf 'old configuration\n' > "$atomic_config"
: > "$MOCK_DOWNLOAD_LOG"
MOCK_DOWNLOAD_MODE=success
export MOCK_DOWNLOAD_MODE
downloadTo 'https://example.invalid/releases/v1/config.conf' "$atomic_config"
assert_equal \
  'downloaded from https://example.invalid/releases/v1/config.conf' \
  "$(cat "$atomic_config")" \
  "Successful download did not atomically replace the destination"
temporary_target=$(cut -d '|' -f 2- "$MOCK_DOWNLOAD_LOG")
assert_equal "$atomic_root" "$(dirname -- "$temporary_target")" \
  "Download temporary file was not created beside its destination"
assert_no_download_temps "$atomic_root" 'config.conf'

printf 'retained after failure\n' > "$atomic_config"
MOCK_DOWNLOAD_MODE=fail
export MOCK_DOWNLOAD_MODE
if downloadTo 'https://example.invalid/failure' "$atomic_config" >/dev/null 2>&1; then
  echo "A failed download unexpectedly succeeded" >&2
  exit 1
fi
assert_equal 'retained after failure' "$(cat "$atomic_config")" \
  "Failed download modified the existing destination"
assert_no_download_temps "$atomic_root" 'config.conf'

printf 'retained after empty download\n' > "$atomic_config"
MOCK_DOWNLOAD_MODE=empty
export MOCK_DOWNLOAD_MODE
if downloadTo 'https://example.invalid/empty' "$atomic_config" >/dev/null 2>&1; then
  echo "An empty download unexpectedly succeeded" >&2
  exit 1
fi
assert_equal 'retained after empty download' "$(cat "$atomic_config")" \
  "Empty download modified the existing destination"
assert_no_download_temps "$atomic_root" 'config.conf'

symlink_target="$atomic_root/symlink-target.conf"
symlink_config="$atomic_root/symlink.conf"
printf 'symlink target\n' > "$symlink_target"
ln -s "$symlink_target" "$symlink_config"
MOCK_DOWNLOAD_MODE=success
export MOCK_DOWNLOAD_MODE
if downloadTo 'https://example.invalid/symlink' "$symlink_config" >/dev/null 2>&1; then
  echo "A symbolic-link download destination was accepted" >&2
  exit 1
fi
if [[ ! -L "$symlink_config" ]]; then
  echo "Symbolic-link destination was unexpectedly replaced" >&2
  exit 1
fi
assert_equal 'symlink target' "$(cat "$symlink_target")" \
  "Rejected symbolic-link download modified its target"
assert_no_download_temps "$atomic_root" 'symlink.conf'

dangling_config="$atomic_root/dangling.conf"
ln -s "$atomic_root/missing-target.conf" "$dangling_config"
if downloadTo 'https://example.invalid/dangling' "$dangling_config" >/dev/null 2>&1; then
  echo "A dangling symbolic-link download destination was accepted" >&2
  exit 1
fi
if [[ ! -L "$dangling_config" ]]; then
  echo "Dangling symbolic-link destination was unexpectedly replaced" >&2
  exit 1
fi
assert_no_download_temps "$atomic_root" 'dangling.conf'

downloadTo() {
  local url="$1"
  local output="$2"

  printf '%s|%s\n' "$url" "$output" >> "$DOWNLOAD_LOG"
  printf 'downloaded private configuration\n' > "$output"
}

# quickStart must select one release and use it for the config, JAR and
# signature, rather than combining a release JAR with config from master.
release_root="$TEST_TMP/release"
release_download_log="$TEST_TMP/release-jars"
release_sign_log="$TEST_TMP/release-signatures"
mkdir -p "$release_root"
getLatestReleaseVersion() {
  printf 'GreatVoyage-v9.9.9\n'
}
mkdirFullNode() {
  mkdir -p "$FULL_NODE_DIR"
  cd "$FULL_NODE_DIR"
}
download() {
  printf '%s|%s\n' "$1" "$2" >> "$release_download_log"
  printf 'release jar\n' > "$2"
}
checkSign() {
  printf '%s\n' "$1" >> "$release_sign_log"
}

: > "$DOWNLOAD_LOG"
: > "$release_download_log"
: > "$release_sign_log"
(
  cd "$release_root"
  FULL_NODE_DIR=FullNode
  # These globals are consumed by the dynamically loaded quickStart function.
  # shellcheck disable=SC2034
  FULL_NODE_CONFIG_MAIN_NET_BASE_URL=https://raw.githubusercontent.com/tronprotocol/java-tron
  # shellcheck disable=SC2034
  RELEASE_URL=https://github.com/tronprotocol/java-tron/releases
  # shellcheck disable=SC2034
  JAR_NAME=FullNode.jar
  quickStart >/dev/null
)
assert_equal \
  'https://raw.githubusercontent.com/tronprotocol/java-tron/GreatVoyage-v9.9.9/framework/src/main/resources/config.conf|config.conf' \
  "$(cat "$DOWNLOAD_LOG")" \
  "Mainnet config URL was not aligned with the selected release"
assert_equal \
  'https://github.com/tronprotocol/java-tron/releases/download/GreatVoyage-v9.9.9/FullNode.jar|FullNode.jar' \
  "$(cat "$release_download_log")" \
  "JAR URL was not aligned with the selected release"
assert_equal 'GreatVoyage-v9.9.9' "$(cat "$release_sign_log")" \
  "Signature verification did not reuse the selected release"

FULL_NODE_CONFIG_PRIVATE_NET=private_net_config.conf
# Used by specifyConfig, which is loaded dynamically from start.sh above.
# shellcheck disable=SC2034
FULL_NODE_CONFIG_PRIVATE_NET_URL=https://example.invalid/private_net_config.conf

# A missing private configuration is downloaded and selected.
missing_root="$TEST_TMP/missing"
FULL_NODE_CONFIG_DIR="$missing_root/config"
DEFAULT_FULL_NODE_CONFIG=config.conf
: > "$DOWNLOAD_LOG"
specifyConfig private >/dev/null
missing_config="$FULL_NODE_CONFIG_DIR/$FULL_NODE_CONFIG_PRIVATE_NET"
assert_equal "$missing_config" "$DEFAULT_FULL_NODE_CONFIG" \
  "Missing private configuration was not selected"
assert_equal "downloaded private configuration" "$(cat "$missing_config")" \
  "Missing private configuration was not downloaded"
assert_equal "1" "$(wc -l < "$DOWNLOAD_LOG" | tr -d ' ')" \
  "Missing private configuration download count is incorrect"

# An existing non-empty private configuration is retained and selected.
existing_root="$TEST_TMP/existing"
FULL_NODE_CONFIG_DIR="$existing_root/config"
existing_config="$FULL_NODE_CONFIG_DIR/$FULL_NODE_CONFIG_PRIVATE_NET"
mkdir -p "$FULL_NODE_CONFIG_DIR"
printf 'retained private configuration\n' > "$existing_config"
DEFAULT_FULL_NODE_CONFIG=config.conf
: > "$DOWNLOAD_LOG"
specifyConfig private >/dev/null
assert_equal "$existing_config" "$DEFAULT_FULL_NODE_CONFIG" \
  "Existing private configuration was not selected"
assert_equal "retained private configuration" "$(cat "$existing_config")" \
  "Existing private configuration was unexpectedly replaced"
if [ -s "$DOWNLOAD_LOG" ]; then
  echo "Existing private configuration unexpectedly triggered a download" >&2
  exit 1
fi

# An empty file is unusable and must be refreshed before it is selected.
empty_root="$TEST_TMP/empty"
FULL_NODE_CONFIG_DIR="$empty_root/config"
empty_config="$FULL_NODE_CONFIG_DIR/$FULL_NODE_CONFIG_PRIVATE_NET"
mkdir -p "$FULL_NODE_CONFIG_DIR"
: > "$empty_config"
DEFAULT_FULL_NODE_CONFIG=config.conf
: > "$DOWNLOAD_LOG"
specifyConfig private >/dev/null
assert_equal "$empty_config" "$DEFAULT_FULL_NODE_CONFIG" \
  "Refreshed empty private configuration was not selected"
assert_equal "downloaded private configuration" "$(cat "$empty_config")" \
  "Empty private configuration was not refreshed"

# A directory at the configuration path must fail closed.
invalid_root="$TEST_TMP/directory"
FULL_NODE_CONFIG_DIR="$invalid_root/config"
mkdir -p "$FULL_NODE_CONFIG_DIR/$FULL_NODE_CONFIG_PRIVATE_NET"
DEFAULT_FULL_NODE_CONFIG=config.conf
if (specifyConfig private) > "$TEST_TMP/invalid-output" 2>&1; then
  echo "A directory at the private configuration path was accepted" >&2
  exit 1
fi
if ! grep -Fq "config path is not a regular file" "$TEST_TMP/invalid-output"; then
  echo "The invalid private configuration path failure was unclear" >&2
  cat "$TEST_TMP/invalid-output" >&2
  exit 1
fi

# Existing private configurations must not bypass the downloadTo symlink
# refusal merely because the linked target is already non-empty.
linked_root="$TEST_TMP/linked"
FULL_NODE_CONFIG_DIR="$linked_root/config"
linked_target="$linked_root/target.conf"
linked_config="$FULL_NODE_CONFIG_DIR/$FULL_NODE_CONFIG_PRIVATE_NET"
mkdir -p "$FULL_NODE_CONFIG_DIR"
printf 'linked private configuration\n' > "$linked_target"
ln -s "$linked_target" "$linked_config"
DEFAULT_FULL_NODE_CONFIG=config.conf
if (specifyConfig private) > "$TEST_TMP/linked-output" 2>&1; then
  echo "An existing symbolic-link private configuration was accepted" >&2
  exit 1
fi
if ! grep -Fq "config path is not a regular file" "$TEST_TMP/linked-output"; then
  echo "The symbolic-link private configuration failure was unclear" >&2
  cat "$TEST_TMP/linked-output" >&2
  exit 1
fi
assert_equal config.conf "$DEFAULT_FULL_NODE_CONFIG" \
  "Rejected symbolic-link config changed the selected configuration"

# Exercise the complete command dispatcher with stable host fixtures. This
# catches duplicate restart calls that function-only tests cannot observe.
command_bin="$TEST_TMP/command-bin"
mock_java_home="$TEST_TMP/java-home"
mkdir -p "$command_bin" "$mock_java_home/bin"
cat > "$command_bin/uname" <<'MOCK_UNAME'
#!/bin/bash
printf 'Darwin\n'
MOCK_UNAME
cat > "$command_bin/sysctl" <<'MOCK_SYSCTL'
#!/bin/bash
printf 'hw.memsize: 17179869184\n'
MOCK_SYSCTL
cat > "$command_bin/ps" <<'MOCK_PS'
#!/bin/bash
exit 0
MOCK_PS
cat > "$command_bin/git" <<'MOCK_GIT'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$START_GIT_LOG"
printf 'deadbeef\trefs/tags/GreatVoyage-v9.9.9\n'
MOCK_GIT
cat > "$mock_java_home/bin/java" <<'MOCK_JAVA'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$START_JAVA_LOG"
MOCK_JAVA
chmod +x "$command_bin/uname" "$command_bin/sysctl" "$command_bin/ps" \
  "$command_bin/git" \
  "$mock_java_home/bin/java"

run_start_script() {
  local case_name="$1"
  shift
  LAST_START_ROOT="$TEST_TMP/command-$case_name"
  LAST_START_LOG="$LAST_START_ROOT/java-invocations"
  LAST_START_OUTPUT="$LAST_START_ROOT/script-output"
  LAST_GIT_LOG="$LAST_START_ROOT/git-invocations"
  mkdir -p "$LAST_START_ROOT"
  touch "$LAST_START_ROOT/FullNode.jar" "$LAST_START_ROOT/config.conf"
  : > "$LAST_START_LOG"
  : > "$LAST_GIT_LOG"
  (
    cd "$LAST_START_ROOT"
    PATH="$command_bin:$PATH" \
      JAVA_HOME="$mock_java_home" \
      JAVACMD="$mock_java_home/bin/java" \
      START_JAVA_LOG="$LAST_START_LOG" \
      START_GIT_LOG="$LAST_GIT_LOG" \
      HOSTNAME=start-script-test \
      bash "$START_SCRIPT" "$@"
  ) > "$LAST_START_OUTPUT" 2>&1
  # startService launches Java in the background; allow the short fixture to
  # append its invocation after the parent shell exits.
  local _
  for _ in {1..50}; do
    if [[ -s "$LAST_START_LOG" ]]; then
      break
    fi
    sleep 0.02
  done
}

assert_single_java_invocation() {
  local message="$1"
  local count
  count=$(wc -l < "$LAST_START_LOG" | tr -d ' ')
  assert_equal 1 "$count" "$message"
}

run_start_script default
assert_single_java_invocation "Default start did not invoke restart exactly once"

run_start_script standalone-run --run
assert_single_java_invocation "Standalone --run did not invoke restart exactly once"

custom_root="$TEST_TMP/command-forwarded-options"
mkdir -p "$custom_root"
touch "$custom_root/FullNode.jar" "$custom_root/config.conf"
run_start_script forwarded-options --run -j FullNode.jar -c config.conf \
  -d custom-output -p 18888
assert_single_java_invocation "Option-bearing --run did not invoke restart exactly once"
if ! grep -Fq -- '-jar FullNode.jar' "$LAST_START_LOG" ||
   ! grep -Fq -- '-c config.conf' "$LAST_START_LOG" ||
   ! grep -Fq -- '-d custom-output' "$LAST_START_LOG" ||
   ! grep -Fq -- '-p 18888' "$LAST_START_LOG"; then
  echo "start.sh did not forward supported run options to Java" >&2
  cat "$LAST_START_LOG" >&2
  exit 1
fi

: > "$MOCK_DOWNLOAD_LOG"
MOCK_DOWNLOAD_MODE=success
export MOCK_DOWNLOAD_MODE
run_start_script release-run --release --run
assert_single_java_invocation "--release --run did not invoke restart exactly once"
if ! grep -Fq \
  'https://raw.githubusercontent.com/tronprotocol/java-tron/GreatVoyage-v9.9.9/framework/src/main/resources/config.conf' \
  "$MOCK_DOWNLOAD_LOG"; then
  echo "--release --run did not download config from the selected release tag" >&2
  cat "$MOCK_DOWNLOAD_LOG" >&2
  exit 1
fi
assert_equal 1 "$(wc -l < "$LAST_GIT_LOG" | tr -d ' ')" \
  "--release --run selected the latest release more than once"

stop_root="$TEST_TMP/command-stop"
stop_log="$stop_root/java-invocations"
stop_output="$stop_root/script-output"
mkdir -p "$stop_root"
: > "$stop_log"
(
  cd "$stop_root"
  PATH="$command_bin:$PATH" \
    JAVA_HOME="$mock_java_home" \
    JAVACMD="$mock_java_home/bin/java" \
    START_JAVA_LOG="$stop_log" \
    bash "$START_SCRIPT" -j FullNode.jar --stop
) > "$stop_output" 2>&1 &
stop_pid=$!
stop_finished=false
for _ in {1..100}; do
  if ! kill -0 "$stop_pid" 2>/dev/null; then
    stop_finished=true
    break
  fi
  sleep 0.02
done
if [[ $stop_finished != true ]]; then
  kill "$stop_pid" 2>/dev/null || true
  wait "$stop_pid" 2>/dev/null || true
  echo "start.sh --stop did not terminate" >&2
  exit 1
fi
if ! wait "$stop_pid"; then
  echo "start.sh --stop failed" >&2
  cat "$stop_output" >&2
  exit 1
fi
assert_equal 1 "$(grep -Fc 'info: java-tron stop' "$stop_output")" \
  "--stop did not execute stopService exactly once"
if [[ -s "$stop_log" ]]; then
  echo "--stop unexpectedly started Java" >&2
  cat "$stop_log" >&2
  exit 1
fi

echo "start.sh configuration, download, and command-dispatch tests passed"
