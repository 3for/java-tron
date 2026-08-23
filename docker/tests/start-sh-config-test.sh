#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
REPOSITORY_ROOT=$(cd -- "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)
START_SCRIPT="$REPOSITORY_ROOT/start.sh"
TEST_TMP=$(mktemp -d)
TEST_TMP=$(cd -- "$TEST_TMP" >/dev/null 2>&1 && pwd -P)
DOWNLOAD_LOG="$TEST_TMP/downloads"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

function_source=$(awk '
  /^(downloadTo\(\) \{|linuxProcessStartTokenFromStat\(\) \{|quickStart\(\) \{|specifyConfig\(\)\{)$/ { capture = 1 }
  capture { print }
  capture && /^}$/ { capture = 0 }
' "$START_SCRIPT")
eval "$function_source"

if ! declare -F specifyConfig >/dev/null ||
   ! declare -F downloadTo >/dev/null ||
   ! declare -F linuxProcessStartTokenFromStat >/dev/null ||
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

# Linux /proc stat parsing must use the delimiter after the complete comm
# field; a process name may itself contain spaces and closing parentheses.
linux_stat='991 (java worker) helper) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 424242 20 21'
assert_equal 424242 "$(linuxProcessStartTokenFromStat "$linux_stat")" \
  "Linux process start time was parsed from the wrong /proc stat field"

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

# Exercise the real downloadTo implementation through a deterministic curl
# fixture before replacing it with the smaller specifyConfig test double.
download_bin="$TEST_TMP/download-bin"
mkdir -p "$download_bin"
cat > "$download_bin/curl" <<'MOCK_CURL'
#!/bin/bash
set -euo pipefail

output=''
proto=''
proto_redir=''
url=''
printf '%s\n' "$*" >> "$MOCK_CURL_ARGUMENT_LOG"
if [[ "${1:-}" != -q ]]; then
  echo 'curl was invoked without -q as its first argument' >&2
  exit 65
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    --proto)
      proto=$2
      shift 2
      ;;
    --proto-redir)
      proto_redir=$2
      shift 2
      ;;
    -q|-fsSL|--tlsv1.2)
      shift
      ;;
    -k|--insecure)
      echo 'curl was allowed to bypass TLS certificate verification' >&2
      exit 65
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

if [[ "$proto" != '=https' || "$proto_redir" != '=https' ]]; then
  echo 'curl did not restrict the initial URL and redirects to HTTPS' >&2
  exit 65
fi
if [[ "$url" != https://* ]]; then
  echo "curl received a non-HTTPS URL: $url" >&2
  exit 65
fi
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
  signature-empty)
    if [[ "$url" == *.sig ]]; then
      : > "$output"
    else
      printf 'downloaded from %s\n' "$url" > "$output"
    fi
    ;;
  *)
    echo "Unexpected download fixture mode: $MOCK_DOWNLOAD_MODE" >&2
    exit 64
    ;;
esac
MOCK_CURL
chmod +x "$download_bin/curl"

atomic_root="$TEST_TMP/atomic-download"
mkdir -p "$atomic_root"
atomic_config="$atomic_root/config.conf"
MOCK_DOWNLOAD_LOG="$TEST_TMP/atomic-downloads"
MOCK_CURL_ARGUMENT_LOG="$TEST_TMP/curl-arguments"
export MOCK_DOWNLOAD_LOG
export MOCK_CURL_ARGUMENT_LOG
PATH="$download_bin:$PATH"
export PATH

printf 'old configuration\n' > "$atomic_config"
: > "$MOCK_DOWNLOAD_LOG"
: > "$MOCK_CURL_ARGUMENT_LOG"
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

curl_call_count=$(wc -l < "$MOCK_CURL_ARGUMENT_LOG" | tr -d ' ')
if downloadTo 'http://example.invalid/insecure' "$atomic_config" >/dev/null 2>&1; then
  echo "A non-HTTPS download URL unexpectedly succeeded" >&2
  exit 1
fi
assert_equal "$curl_call_count" \
  "$(wc -l < "$MOCK_CURL_ARGUMENT_LOG" | tr -d ' ')" \
  "A non-HTTPS URL reached curl before it was rejected"

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
mkdir -p "$release_root"
getLatestReleaseVersion() {
  printf 'GreatVoyage-v9.9.9\n'
}
mkdirFullNode() {
  mkdir -p "$FULL_NODE_DIR"
  cd "$FULL_NODE_DIR"
}
installVerifiedReleaseArtifact() {
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$release_download_log"
  printf 'release jar\n' > "$3"
}

: > "$DOWNLOAD_LOG"
: > "$release_download_log"
(
  cd "$release_root"
  FULL_NODE_DIR=FullNode
  # These globals are consumed by the dynamically loaded quickStart function.
  # shellcheck disable=SC2034
  FULL_NODE_CONFIG_MAIN_NET_BASE_URL=https://raw.githubusercontent.com/tronprotocol/java-tron
  # shellcheck disable=SC2034
  RELEASE_URL=https://github.com/tronprotocol/java-tron/releases
  # shellcheck disable=SC2034
  RELEASE_FULL_NODE_ASSET=FullNode.jar
  # shellcheck disable=SC2034
  JAR_NAME=FullNode.jar
  quickStart >/dev/null
)
assert_equal \
  'https://raw.githubusercontent.com/tronprotocol/java-tron/GreatVoyage-v9.9.9/framework/src/main/resources/config.conf|config.conf' \
  "$(cat "$DOWNLOAD_LOG")" \
  "Mainnet config URL was not aligned with the selected release"
assert_equal \
  'GreatVoyage-v9.9.9|FullNode.jar|FullNode.jar' \
  "$(cat "$release_download_log")" \
  "Verified JAR installation was not aligned with the selected release"

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
printf '%s\n' "${START_UNAME_OUTPUT:-Darwin}"
MOCK_UNAME
cat > "$command_bin/sysctl" <<'MOCK_SYSCTL'
#!/bin/bash
printf 'hw.memsize: 17179869184\n'
MOCK_SYSCTL
cat > "$command_bin/ps" <<'MOCK_PS'
#!/bin/bash
set -euo pipefail

if [[ $# -eq 4 && "$1" == -p && "$3" == -o && "$4" == lstart= ]]; then
  candidate_pid=$2
  if [[ -n "${START_PROCESS_TOKEN_SEQUENCE_DIR:-}" ]]; then
    token_count=0
    if [[ -f "$START_PROCESS_TOKEN_SEQUENCE_DIR/count" ]]; then
      read -r token_count < "$START_PROCESS_TOKEN_SEQUENCE_DIR/count"
    fi
    token_count=$((token_count + 1))
    printf '%s\n' "$token_count" > "$START_PROCESS_TOKEN_SEQUENCE_DIR/count"
    token_file="$START_PROCESS_TOKEN_SEQUENCE_DIR/$token_count"
    if [[ ! -f "$token_file" ]]; then
      exit 1
    fi
    awk -F '|' -v pid="$candidate_pid" \
      '$1 == pid { print substr($0, index($0, "|") + 1); found = 1; exit }
       END { exit !found }' "$token_file"
    exit
  fi
  if [[ -n "${START_PROCESS_TOKEN_FILE:-}" &&
        -f "$START_PROCESS_TOKEN_FILE" ]]; then
    awk -F '|' -v pid="$candidate_pid" \
      '$1 == pid { print substr($0, index($0, "|") + 1); found = 1; exit }
       END { exit !found }' "$START_PROCESS_TOKEN_FILE"
    exit
  fi
  exit 1
fi

if [[ -n "${START_PS_ARGUMENT_LOG:-}" ]]; then
  printf '%s\n' "$*" >> "$START_PS_ARGUMENT_LOG"
fi
if [[ -n "${START_PS_SEQUENCE_DIR:-}" ]]; then
  ps_count=0
  if [[ -f "$START_PS_SEQUENCE_DIR/count" ]]; then
    read -r ps_count < "$START_PS_SEQUENCE_DIR/count"
  fi
  ps_count=$((ps_count + 1))
  printf '%s\n' "$ps_count" > "$START_PS_SEQUENCE_DIR/count"
  ps_file="$START_PS_SEQUENCE_DIR/$ps_count"
  if [[ -f "$ps_file" ]]; then
    cat "$ps_file"
  fi
  exit 0
fi
if [[ -n "${START_PS_OUTPUT:-}" ]]; then
  printf '%s\n' "$START_PS_OUTPUT"
fi
MOCK_PS
cat > "$command_bin/lsof" <<'MOCK_LSOF'
#!/bin/bash
set -euo pipefail

candidate_pid=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      candidate_pid=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -z "$candidate_pid" || -z "${START_PROCESS_CWD_FILE:-}" ||
      ! -f "$START_PROCESS_CWD_FILE" ]]; then
  exit 1
fi
process_cwd=$(awk -F '|' -v pid="$candidate_pid" \
  '$1 == pid { print substr($0, index($0, "|") + 1); found = 1; exit }
   END { exit !found }' "$START_PROCESS_CWD_FILE") || exit 1
printf 'p%s\nfcwd\nn%s\n' "$candidate_pid" "$process_cwd"
MOCK_LSOF
cat > "$command_bin/sleep" <<'MOCK_SLEEP'
#!/bin/bash
exit 0
MOCK_SLEEP
cat > "$command_bin/git" <<'MOCK_GIT'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$START_GIT_LOG"
printf 'deadbeef\trefs/tags/GreatVoyage-v9.9.9\n'
MOCK_GIT
cat > "$command_bin/gpg" <<'MOCK_GPG'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "$START_GPG_LOG"
if [[ " $* " == *' --recv-keys '* ]]; then
  if [[ "$START_GPG_MODE" == import-failure ]]; then
    exit 2
  fi
  exit 0
fi
if [[ " $* " == *' --with-colons '* ]]; then
  if [[ "$START_GPG_MODE" == fingerprint-mismatch ]]; then
    printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
  else
    printf 'fpr:::::::::07B23298AEA4E006BD9A42DE785FB96D2C7C3CA5:\n'
    printf 'fpr:::::::::1254F859D2B1BD9F66E7107DF859BCB44A28290B:\n'
  fi
  exit 0
fi
if [[ " $* " == *' --verify '* ]]; then
  case "$START_GPG_MODE" in
    valid)
      printf '[GNUPG:] VALIDSIG 1254F859D2B1BD9F66E7107DF859BCB44A28290B 2026-08-23 1787463565 0 4 0 1 10 00 07B23298AEA4E006BD9A42DE785FB96D2C7C3CA5\n'
      ;;
    wrong-primary)
      printf '[GNUPG:] VALIDSIG AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 2026-08-23 1787463565 0 4 0 1 10 00 BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n'
      ;;
    duplicate-valid)
      printf '[GNUPG:] VALIDSIG 1254F859D2B1BD9F66E7107DF859BCB44A28290B 2026-08-23 1787463565 0 4 0 1 10 00 07B23298AEA4E006BD9A42DE785FB96D2C7C3CA5\n'
      printf '[GNUPG:] VALIDSIG 1254F859D2B1BD9F66E7107DF859BCB44A28290B 2026-08-23 1787463565 0 4 0 1 10 00 07B23298AEA4E006BD9A42DE785FB96D2C7C3CA5\n'
      ;;
    bad-signature)
      printf '[GNUPG:] BADSIG F859BCB44A28290B build_tron <build@tron.network>\n'
      exit 1
      ;;
    *)
      echo "Unexpected GPG fixture mode: $START_GPG_MODE" >&2
      exit 64
      ;;
  esac
  exit 0
fi

echo "Unexpected gpg invocation: $*" >&2
exit 64
MOCK_GPG
cat > "$mock_java_home/bin/java" <<'MOCK_JAVA'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$START_JAVA_LOG"
MOCK_JAVA
chmod +x "$command_bin/uname" "$command_bin/sysctl" "$command_bin/ps" \
  "$command_bin/lsof" "$command_bin/sleep" \
  "$command_bin/git" "$command_bin/gpg" \
  "$mock_java_home/bin/java"

start_bash_env="$TEST_TMP/start-bash-env"
cat > "$start_bash_env" <<'MOCK_BASH_ENV'
kill() {
  printf '%s\n' "$*" >> "$START_KILL_LOG"
  return 0
}
MOCK_BASH_ENV

run_start_script_capture() {
  local case_name="$1"
  shift
  LAST_START_ROOT="$TEST_TMP/command-$case_name"
  LAST_START_LOG="$LAST_START_ROOT/java-invocations"
  LAST_START_OUTPUT="$LAST_START_ROOT/script-output"
  LAST_GIT_LOG="$LAST_START_ROOT/git-invocations"
  LAST_GPG_LOG="$LAST_START_ROOT/gpg-invocations"
  LAST_KILL_LOG="$LAST_START_ROOT/kill-invocations"
  LAST_PS_ARGUMENT_LOG="$LAST_START_ROOT/ps-arguments"
  mkdir -p "$LAST_START_ROOT/tmp"
  if [[ "${START_CREATE_DEFAULT_JAR:-true}" == true ]]; then
    printf '%s' "${START_INITIAL_JAR_CONTENT:-existing jar}" > \
      "$LAST_START_ROOT/FullNode.jar"
  fi
  if [[ -n "${START_INITIAL_BACKUP_CONTENT+x}" ]]; then
    printf '%s' "$START_INITIAL_BACKUP_CONTENT" > \
      "$LAST_START_ROOT/FullNode.jar_bak"
  fi
  touch "$LAST_START_ROOT/config.conf"
  if [[ "${START_CREATE_DATABASE:-false}" == true ]]; then
    mkdir -p "$LAST_START_ROOT/data/database"
  fi
  : > "$LAST_START_LOG"
  : > "$LAST_GIT_LOG"
  : > "$LAST_GPG_LOG"
  : > "$LAST_KILL_LOG"
  : > "$LAST_PS_ARGUMENT_LOG"
  if (
    cd "$LAST_START_ROOT"
    PATH="$command_bin:$PATH" \
      JAVA_HOME="$mock_java_home" \
      JAVACMD="$mock_java_home/bin/java" \
      START_JAVA_LOG="$LAST_START_LOG" \
      START_GIT_LOG="$LAST_GIT_LOG" \
      START_GPG_LOG="$LAST_GPG_LOG" \
      START_GPG_MODE="${START_GPG_MODE:-valid}" \
      START_KILL_LOG="$LAST_KILL_LOG" \
      START_PROCESS_CWD_FILE="${START_PROCESS_CWD_FILE:-}" \
      START_PROCESS_TOKEN_FILE="${START_PROCESS_TOKEN_FILE:-}" \
      START_PROCESS_TOKEN_SEQUENCE_DIR="${START_PROCESS_TOKEN_SEQUENCE_DIR:-}" \
      START_PS_ARGUMENT_LOG="$LAST_PS_ARGUMENT_LOG" \
      START_PS_OUTPUT="${START_PS_OUTPUT:-}" \
      START_PS_SEQUENCE_DIR="${START_PS_SEQUENCE_DIR:-}" \
      START_UNAME_OUTPUT="${START_UNAME_OUTPUT:-Darwin}" \
      BASH_ENV="$start_bash_env" \
      TMPDIR="$LAST_START_ROOT/tmp" \
      HOSTNAME=start-script-test \
      bash "$START_SCRIPT" "$@"
  ) > "$LAST_START_OUTPUT" 2>&1; then
    LAST_START_STATUS=0
  else
    LAST_START_STATUS=$?
  fi
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

run_start_script() {
  run_start_script_capture "$@"
  if [[ "$LAST_START_STATUS" -ne 0 ]]; then
    echo "start.sh unexpectedly failed with status $LAST_START_STATUS" >&2
    cat "$LAST_START_OUTPUT" >&2
    exit 1
  fi
}

run_start_script_expect_failure() {
  run_start_script_capture "$@"
  if [[ "$LAST_START_STATUS" -eq 0 ]]; then
    echo 'start.sh unexpectedly succeeded' >&2
    cat "$LAST_START_OUTPUT" >&2
    exit 1
  fi
}

assert_single_java_invocation() {
  local message="$1"
  local count
  count=$(wc -l < "$LAST_START_LOG" | tr -d ' ')
  assert_equal 1 "$count" "$message"
}

assert_no_java_invocation() {
  local message="$1"

  if [[ -s "$LAST_START_LOG" ]]; then
    echo "$message" >&2
    cat "$LAST_START_LOG" >&2
    exit 1
  fi
}

assert_no_release_temps() {
  local leftover

  leftover=$(find "$LAST_START_ROOT" -type f \
    \( -name '.*.artifact.*' -o -name '.*.signature.*' -o \
      -name '.*_bak.*' \) -print -quit)
  if [[ -n "$leftover" ]]; then
    echo "Release temporary file was not cleaned up: $leftover" >&2
    exit 1
  fi
  leftover=$(find "$LAST_START_ROOT/tmp" -mindepth 1 -maxdepth 1 -print -quit)
  if [[ -n "$leftover" ]]; then
    echo "Temporary GPG home was not cleaned up: $leftover" >&2
    exit 1
  fi
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
if ! grep -Fq -- "-jar $LAST_START_ROOT/FullNode.jar" "$LAST_START_LOG" ||
   ! grep -Fq -- '-c config.conf' "$LAST_START_LOG" ||
   ! grep -Fq -- '-d custom-output' "$LAST_START_LOG" ||
   ! grep -Fq -- '-p 18888' "$LAST_START_LOG"; then
  echo "start.sh did not forward supported run options to Java" >&2
  cat "$LAST_START_LOG" >&2
  exit 1
fi

# An absolute custom JAR must remain intact across the pre-start process check.
# A different node with the same basename must not be mistaken for this target.
absolute_node_root="$TEST_TMP/absolute-node"
absolute_node_jar="$absolute_node_root/FullNode.jar"
other_node_root="$TEST_TMP/other-node"
other_node_jar="$other_node_root/FullNode.jar"
mkdir -p "$absolute_node_root" "$other_node_root"
printf 'absolute node jar\n' > "$absolute_node_jar"
printf 'other node jar\n' > "$other_node_jar"
long_process_option=$(printf 'x%.0s' {1..300})
different_cwd_file="$TEST_TMP/different-cwd-map"
printf '991001|%s\n' "$other_node_root" > "$different_cwd_file"
START_CREATE_DEFAULT_JAR=false
START_PROCESS_CWD_FILE="$different_cwd_file"
START_PS_OUTPUT="991001 java -Dpadding=$long_process_option -jar FullNode.jar -c other.conf"
run_start_script absolute-jar --run -j "$absolute_node_jar"
unset START_CREATE_DEFAULT_JAR START_PROCESS_CWD_FILE START_PS_OUTPUT
assert_single_java_invocation \
  "An absolute -j path did not start exactly one node"
if ! grep -Fq -- "-jar $absolute_node_jar" "$LAST_START_LOG"; then
  echo "start.sh did not preserve the absolute -j path passed to Java" >&2
  cat "$LAST_START_LOG" >&2
  exit 1
fi
if [[ -s "$LAST_KILL_LOG" ]]; then
  echo "start.sh signalled a different node with the same JAR basename" >&2
  cat "$LAST_KILL_LOG" >&2
  exit 1
fi
if [[ -s "$LAST_PS_ARGUMENT_LOG" ]] &&
   awk '$0 != "-ww -eo pid=,args=" { exit 1 }' "$LAST_PS_ARGUMENT_LOG"; then
  :
else
  echo "start.sh did not request untruncated PID and argument output from ps" >&2
  cat "$LAST_PS_ARGUMENT_LOG" >&2
  exit 1
fi
assert_equal 1 "$(wc -l < "$LAST_PS_ARGUMENT_LOG" | tr -d ' ')" \
  "startService searched the process table instead of reporting its launched PID"
if ! grep -Eq 'info: start java-tron with pid [0-9]+ on start-script-test' \
  "$LAST_START_OUTPUT"; then
  echo "start.sh did not report the PID returned by the background launch" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# Nodes launched by older versions used a relative -jar argument. Resolve that
# argument against the process's real cwd so a unique legacy node remains
# stoppable without falling back to basename matching.
legacy_root="$TEST_TMP/command-relative-legacy"
legacy_cwd_file="$TEST_TMP/relative-legacy-cwd"
legacy_token_file="$TEST_TMP/relative-legacy-token"
legacy_ps_sequence="$TEST_TMP/relative-legacy-ps"
mkdir -p "$legacy_ps_sequence"
printf '991101|%s\n' "$legacy_root" > "$legacy_cwd_file"
printf '991101|Sun Aug 23 10:00:00 2026\n' > "$legacy_token_file"
printf '991101 java -Xmx4g -jar FullNode.jar -c config.conf\n' > \
  "$legacy_ps_sequence/1"
cp "$legacy_ps_sequence/1" "$legacy_ps_sequence/2"
: > "$legacy_ps_sequence/3"
START_PROCESS_CWD_FILE="$legacy_cwd_file"
START_PROCESS_TOKEN_FILE="$legacy_token_file"
START_PS_SEQUENCE_DIR="$legacy_ps_sequence"
run_start_script relative-legacy --stop
unset START_PROCESS_CWD_FILE START_PROCESS_TOKEN_FILE START_PS_SEQUENCE_DIR
assert_no_java_invocation "Stopping a legacy relative-path node started Java"
assert_equal '-15 991101' "$(cat "$LAST_KILL_LOG")" \
  "A unique legacy relative-path node was not stopped with TERM only"
if ! grep -Fq 'info: java-tron stop' "$LAST_START_OUTPUT"; then
  echo "Stopping a unique legacy relative-path node did not report success" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# If a legacy relative-path process's cwd cannot be established, treating its
# basename as the target would be unsafe. Refuse both signalling and restart.
START_PS_OUTPUT='991106 java -jar FullNode.jar -c config.conf'
run_start_script_expect_failure unresolved-cwd --run
unset START_PS_OUTPUT
assert_no_java_invocation \
  "start.sh launched Java after it could not resolve a legacy process cwd"
if [[ -s "$LAST_KILL_LOG" ]]; then
  echo "start.sh signalled a relative-path process whose cwd was unknown" >&2
  cat "$LAST_KILL_LOG" >&2
  exit 1
fi
if ! grep -Fq 'could not determine the working directory' "$LAST_START_OUTPUT"; then
  echo "The unresolved-cwd refusal did not explain why it failed closed" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# A unique process using the selected absolute JAR path is also stopped, while
# subsequent scans confirm that the original PID—not a new match—has exited.
absolute_stop_root="$TEST_TMP/command-unique-absolute"
absolute_stop_jar="$absolute_stop_root/FullNode.jar"
absolute_token_file="$TEST_TMP/absolute-stop-token"
absolute_ps_sequence="$TEST_TMP/absolute-stop-ps"
mkdir -p "$absolute_ps_sequence"
printf '991111|Sun Aug 23 10:01:00 2026\n' > "$absolute_token_file"
printf '991111 java -jar %s -c config.conf\n' "$absolute_stop_jar" > \
  "$absolute_ps_sequence/1"
cp "$absolute_ps_sequence/1" "$absolute_ps_sequence/2"
: > "$absolute_ps_sequence/3"
START_PROCESS_TOKEN_FILE="$absolute_token_file"
START_PS_SEQUENCE_DIR="$absolute_ps_sequence"
run_start_script unique-absolute --stop
unset START_PROCESS_TOKEN_FILE START_PS_SEQUENCE_DIR
assert_no_java_invocation "Stopping a unique absolute-path node started Java"
assert_equal '-15 991111' "$(cat "$LAST_KILL_LOG")" \
  "A unique absolute-path node was not stopped with TERM only"

# A live exact match without a trustworthy platform start token is not safe to
# signal: PID plus command line alone cannot exclude PID reuse.
missing_token_root="$TEST_TMP/command-missing-start-token"
missing_token_jar="$missing_token_root/FullNode.jar"
START_PS_OUTPUT="991116 java -jar $missing_token_jar"
run_start_script_expect_failure missing-start-token --run
unset START_PS_OUTPUT
assert_no_java_invocation \
  "restart launched Java when process start identity was unavailable"
if [[ -s "$LAST_KILL_LOG" ]]; then
  echo "start.sh signalled a process without verifying its start identity" >&2
  cat "$LAST_KILL_LOG" >&2
  exit 1
fi
if ! grep -Fq 'cannot verify the start identity' "$LAST_START_OUTPUT"; then
  echo "The unavailable start-identity refusal was unclear" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# If the exact JAR match changes PID between discovery and the pre-TERM scan,
# fail without signalling either process or starting a replacement node.
changed_pid_root="$TEST_TMP/command-changed-pid"
changed_pid_jar="$changed_pid_root/FullNode.jar"
changed_pid_token_file="$TEST_TMP/changed-pid-token"
changed_pid_ps_sequence="$TEST_TMP/changed-pid-ps"
mkdir -p "$changed_pid_ps_sequence"
printf '991121|Sun Aug 23 10:02:00 2026\n' > "$changed_pid_token_file"
printf '991121 java -jar %s\n' "$changed_pid_jar" > \
  "$changed_pid_ps_sequence/1"
printf '991122 java -jar %s\n' "$changed_pid_jar" > \
  "$changed_pid_ps_sequence/2"
START_PROCESS_TOKEN_FILE="$changed_pid_token_file"
START_PS_SEQUENCE_DIR="$changed_pid_ps_sequence"
run_start_script_expect_failure changed-pid --run
unset START_PROCESS_TOKEN_FILE START_PS_SEQUENCE_DIR
assert_no_java_invocation \
  "start.sh launched Java after the selected process changed PID"
if [[ -s "$LAST_KILL_LOG" ]]; then
  echo "start.sh signalled a process after the selected PID changed" >&2
  cat "$LAST_KILL_LOG" >&2
  exit 1
fi
if ! grep -Fq 'changed from PID 991121 to PID 991122' "$LAST_START_OUTPUT"; then
  echo "The changed-PID refusal did not identify the process replacement" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# A replacement appearing after TERM must not inherit the original stop
# operation. In particular, restart must fail before launching another node.
post_term_root="$TEST_TMP/command-post-term-pid-change"
post_term_jar="$post_term_root/FullNode.jar"
post_term_token_file="$TEST_TMP/post-term-token"
post_term_ps_sequence="$TEST_TMP/post-term-ps"
mkdir -p "$post_term_ps_sequence"
printf '991126|Sun Aug 23 10:02:30 2026\n' > "$post_term_token_file"
printf '991126 java -jar %s\n' "$post_term_jar" > \
  "$post_term_ps_sequence/1"
cp "$post_term_ps_sequence/1" "$post_term_ps_sequence/2"
printf '991127 java -jar %s\n' "$post_term_jar" > \
  "$post_term_ps_sequence/3"
START_PROCESS_TOKEN_FILE="$post_term_token_file"
START_PS_SEQUENCE_DIR="$post_term_ps_sequence"
run_start_script_expect_failure post-term-pid-change --run
unset START_PROCESS_TOKEN_FILE START_PS_SEQUENCE_DIR
assert_no_java_invocation \
  "restart launched Java after the stopped process was replaced by a new PID"
assert_equal '-15 991126' "$(cat "$LAST_KILL_LOG")" \
  "start.sh signalled a replacement PID after TERM"
if ! grep -Fq 'changed from PID 991126 to PID 991127' "$LAST_START_OUTPUT"; then
  echo "The post-TERM PID replacement refusal was unclear" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# PID reuse with the same JAR command line is distinguishable by process start
# time. Once TERM has been sent to the original identity, never KILL a new
# process that reuses both its PID and JAR path.
reused_pid_root="$TEST_TMP/command-reused-pid"
reused_pid_jar="$reused_pid_root/FullNode.jar"
reused_pid_ps_sequence="$TEST_TMP/reused-pid-ps"
reused_pid_token_sequence="$TEST_TMP/reused-pid-tokens"
mkdir -p "$reused_pid_ps_sequence" "$reused_pid_token_sequence"
printf '991131 java -jar %s\n' "$reused_pid_jar" > \
  "$reused_pid_ps_sequence/1"
cp "$reused_pid_ps_sequence/1" "$reused_pid_ps_sequence/2"
cp "$reused_pid_ps_sequence/1" "$reused_pid_ps_sequence/3"
printf '991131|Sun Aug 23 10:03:00 2026\n' > \
  "$reused_pid_token_sequence/1"
cp "$reused_pid_token_sequence/1" "$reused_pid_token_sequence/2"
printf '991131|Sun Aug 23 10:03:01 2026\n' > \
  "$reused_pid_token_sequence/3"
START_PROCESS_TOKEN_SEQUENCE_DIR="$reused_pid_token_sequence"
START_PS_SEQUENCE_DIR="$reused_pid_ps_sequence"
run_start_script_expect_failure reused-pid --stop
unset START_PROCESS_TOKEN_SEQUENCE_DIR START_PS_SEQUENCE_DIR
assert_no_java_invocation "The PID-reuse stop path unexpectedly started Java"
assert_equal '-15 991131' "$(cat "$LAST_KILL_LOG")" \
  "start.sh sent another signal after the selected PID's start identity changed"
if ! grep -Fq 'start identity of java-tron PID 991131 changed' \
  "$LAST_START_OUTPUT"; then
  echo "The PID-reuse refusal did not explain the changed start identity" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# More than one process using the exact selected JAR is ambiguous. The script
# must fail closed without signalling either PID or starting another node.
multiple_root="$TEST_TMP/command-multiple-exact"
multiple_jar="$multiple_root/FullNode.jar"
START_PS_OUTPUT="991011 java -jar $multiple_jar -c first.conf
991012 java -jar $multiple_jar -c second.conf"
run_start_script_expect_failure multiple-exact --run
unset START_PS_OUTPUT
assert_no_java_invocation \
  "start.sh started Java after finding multiple exact JAR matches"
if [[ -s "$LAST_KILL_LOG" ]]; then
  echo "start.sh signalled a process after finding multiple exact JAR matches" >&2
  cat "$LAST_KILL_LOG" >&2
  exit 1
fi
if ! grep -Fq 'multiple processes use the exact jar path' "$LAST_START_OUTPUT" ||
   ! grep -Fq 'confirm the intended PID and stop it manually' "$LAST_START_OUTPUT"; then
  echo "The multiple-process refusal did not explain the manual action required" >&2
  cat "$LAST_START_OUTPUT" >&2
  exit 1
fi

# Support the documented spelling and retain the historical misspelling as a
# compatibility alias. Both must skip ArchiveManifest execution.
for disable_flag in --disable-rewrite-manifest --disable-rewrite-manifes; do
  case_name=${disable_flag#--}
  START_CREATE_DATABASE=true
  run_start_script "$case_name" --run -d data "$disable_flag"
  unset START_CREATE_DATABASE
  assert_single_java_invocation \
    "$disable_flag did not disable manifest rebuilding"
  if ! grep -Fq 'info: disable rebuild manifest!' "$LAST_START_OUTPUT"; then
    echo "$disable_flag was not recognized by start.sh" >&2
    cat "$LAST_START_OUTPUT" >&2
    exit 1
  fi
done

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
if ! grep -Fq -- '--recv-keys 07B23298AEA4E006BD9A42DE785FB96D2C7C3CA5' \
  "$LAST_GPG_LOG" ||
   ! grep -Fq -- '--status-fd 1 --verify' "$LAST_GPG_LOG"; then
  echo "--release --run did not import the pinned key and verify the detached signature" >&2
  cat "$LAST_GPG_LOG" >&2
  exit 1
fi
assert_no_release_temps

# An invalid release signature must fail closed before Java starts and must not
# install the downloaded artifact.
START_GPG_MODE=bad-signature
run_start_script_expect_failure release-bad-signature --release --run
unset START_GPG_MODE
assert_no_java_invocation \
  "--release --run started Java after signature verification failed"
if [[ -e "$LAST_START_ROOT/FullNode/FullNode.jar" ]]; then
  echo "--release --run installed a JAR with an invalid signature" >&2
  exit 1
fi
assert_no_release_temps

# Upgrade retains the old JAR until verification succeeds, then atomically
# installs the new JAR and keeps the prior version as a backup.
run_start_script upgrade-valid --upgrade --run
assert_single_java_invocation "A verified --upgrade did not restart exactly once"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar_bak")" \
  "A verified --upgrade did not retain the previous JAR as a backup"
assert_equal \
  'downloaded from https://github.com/tronprotocol/java-tron/releases/download/GreatVoyage-v9.9.9/FullNode.jar' \
  "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "A verified --upgrade did not install the downloaded JAR"
assert_no_release_temps

START_INITIAL_BACKUP_CONTENT='retained older backup'
START_GPG_MODE=wrong-primary
run_start_script_expect_failure upgrade-wrong-primary --upgrade --run
unset START_GPG_MODE START_INITIAL_BACKUP_CONTENT
assert_no_java_invocation \
  "--upgrade started Java after a signature from an unpinned primary key"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "A failed --upgrade modified the existing JAR"
assert_equal 'retained older backup' \
  "$(cat "$LAST_START_ROOT/FullNode.jar_bak")" \
  "A failed --upgrade modified the existing backup"
assert_no_release_temps

START_INITIAL_BACKUP_CONTENT='retained after empty signature'
MOCK_DOWNLOAD_MODE=signature-empty
export MOCK_DOWNLOAD_MODE
run_start_script_expect_failure upgrade-empty-signature --upgrade --run
MOCK_DOWNLOAD_MODE=success
export MOCK_DOWNLOAD_MODE
unset START_INITIAL_BACKUP_CONTENT
assert_no_java_invocation \
  "--upgrade started Java after downloading an empty detached signature"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "An empty detached signature caused --upgrade to replace the existing JAR"
assert_equal 'retained after empty signature' \
  "$(cat "$LAST_START_ROOT/FullNode.jar_bak")" \
  "An empty detached signature caused --upgrade to modify the existing backup"
assert_no_release_temps

START_INITIAL_BACKUP_CONTENT='retained after interrupted download'
MOCK_DOWNLOAD_MODE=fail
export MOCK_DOWNLOAD_MODE
run_start_script_expect_failure upgrade-partial-download --upgrade --run
MOCK_DOWNLOAD_MODE=success
export MOCK_DOWNLOAD_MODE
unset START_INITIAL_BACKUP_CONTENT
assert_no_java_invocation \
  "--upgrade started Java after an interrupted artifact download"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "An interrupted artifact download replaced the existing JAR"
assert_equal 'retained after interrupted download' \
  "$(cat "$LAST_START_ROOT/FullNode.jar_bak")" \
  "An interrupted artifact download modified the existing backup"
assert_no_release_temps

# --download shares the verified installation boundary but exits without
# running the downloaded JAR.
run_start_script verified-download --download
assert_no_java_invocation "--download unexpectedly started Java"
assert_equal \
  'downloaded from https://github.com/tronprotocol/java-tron/releases/download/GreatVoyage-v9.9.9/FullNode.jar' \
  "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "--download did not install the verified FullNode JAR"
assert_no_release_temps

absolute_release_dir="$TEST_TMP/absolute-release-target"
absolute_release_jar="$absolute_release_dir/renamed-node.jar"
mkdir -p "$absolute_release_dir"
printf 'existing renamed jar' > "$absolute_release_jar"
run_start_script absolute-verified-download --download -j "$absolute_release_jar"
assert_no_java_invocation "An absolute-path --download unexpectedly started Java"
assert_equal \
  'downloaded from https://github.com/tronprotocol/java-tron/releases/download/GreatVoyage-v9.9.9/FullNode.jar' \
  "$(cat "$absolute_release_jar")" \
  "An absolute custom JAR path changed the official release asset name"
if find "$absolute_release_dir" -maxdepth 1 -type f \
  \( -name '.*.artifact.*' -o -name '.*.signature.*' \) | grep -q .; then
  echo "An absolute-path verified download left temporary release files" >&2
  exit 1
fi
assert_no_release_temps

START_GPG_MODE=fingerprint-mismatch
run_start_script_expect_failure download-fingerprint-mismatch --download
unset START_GPG_MODE
assert_no_java_invocation \
  "--download started Java after the imported key fingerprint mismatched"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "A failed --download modified the existing JAR"
assert_no_release_temps

START_GPG_MODE=duplicate-valid
run_start_script_expect_failure download-duplicate-valid --download
unset START_GPG_MODE
assert_no_java_invocation \
  "--download accepted more than one VALIDSIG record"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "Duplicate VALIDSIG records caused --download to modify the existing JAR"
assert_no_release_temps

START_GPG_MODE=import-failure
run_start_script_expect_failure download-key-import-failure --download
unset START_GPG_MODE
assert_no_java_invocation \
  "--download started Java after the pinned key import failed"
assert_equal 'existing jar' "$(cat "$LAST_START_ROOT/FullNode.jar")" \
  "A key import failure caused --download to modify the existing JAR"
assert_no_release_temps

# A downloaded ArchiveManifest JAR is executable code too, so the automatic
# rebuild path must verify it through the same pinned release key first.
START_CREATE_DATABASE=true
run_start_script archive-verified --run -d data
unset START_CREATE_DATABASE
for _ in {1..50}; do
  if [[ $(wc -l < "$LAST_START_LOG" | tr -d ' ') -ge 2 ]]; then
    break
  fi
  sleep 0.02
done
assert_equal 2 "$(wc -l < "$LAST_START_LOG" | tr -d ' ')" \
  "The verified manifest rebuild and node start did not each invoke Java once"
if ! grep -Fq -- '-jar ArchiveManifest.jar -d data/database' "$LAST_START_LOG"; then
  echo "The verified ArchiveManifest JAR was not executed with the selected database" >&2
  cat "$LAST_START_LOG" >&2
  exit 1
fi
assert_no_release_temps

START_CREATE_DATABASE=true
START_GPG_MODE=bad-signature
run_start_script_expect_failure archive-bad-signature --run -d data
unset START_CREATE_DATABASE START_GPG_MODE
assert_no_java_invocation \
  "Java ran after ArchiveManifest signature verification failed"
if [[ -e "$LAST_START_ROOT/ArchiveManifest.jar" ]]; then
  echo "An ArchiveManifest JAR with an invalid signature was installed" >&2
  exit 1
fi
assert_no_release_temps

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

if grep -Eq -- '(^| )(-k|--insecure)( |$)' "$MOCK_CURL_ARGUMENT_LOG"; then
  echo "start.sh disabled TLS certificate verification for curl" >&2
  cat "$MOCK_CURL_ARGUMENT_LOG" >&2
  exit 1
fi
if awk '$1 != "-q" || index($0, "--proto =https") == 0 ||
    index($0, "--proto-redir =https") == 0 { insecure = 1 }
    END { exit insecure }' "$MOCK_CURL_ARGUMENT_LOG"; then
  :
else
  echo "start.sh invoked curl without isolating config and restricting redirects to HTTPS" >&2
  cat "$MOCK_CURL_ARGUMENT_LOG" >&2
  exit 1
fi

echo "start.sh configuration, download, and command-dispatch tests passed"
