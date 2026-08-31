#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_SCRIPT="$SCRIPT_DIR/../docker.sh"
TEST_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/java-tron-docker-test.XXXXXX")"
TEST_DIRECTORY="$(cd "$TEST_DIRECTORY" && pwd)"
MOCK_BINARY_DIRECTORY="$TEST_DIRECTORY/bin"
MOCK_DOWNLOAD_CONTENT="downloaded private configuration"
export MOCK_DOWNLOAD_CONTENT

CASE_DIRECTORY=""
DOCKER_CALL_LOG=""
DOCKER_RUN_ARGS_LOG=""
DOWNLOAD_CALL_LOG=""
COMMAND_OUTPUT=""

cleanup() {
  rm -rf "$TEST_DIRECTORY"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

docker() {
  if [[ "${1:-}" == "info" ]]; then
    return 0
  fi

  if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then
    return 0
  fi

  printf '%s\n' "${1:-}" >> "$DOCKER_CALL_LOG"
  if [[ "${1:-}" == "run" ]]; then
    shift
    printf '%s\n' "$@" > "$DOCKER_RUN_ARGS_LOG"
  fi
}
export -f docker

curl() {
  local output_file=""

  printf '%s\n' "$*" >> "$DOWNLOAD_CALL_LOG"
  if [[ "${MOCK_CURL_FAIL:-false}" == "true" ]]; then
    return 22
  fi

  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--output" ]]; then
      output_file=$2
      break
    fi
    shift
  done

  [[ -n "$output_file" ]] || return 2
  printf '%s\n' "$MOCK_DOWNLOAD_CONTENT" > "$output_file"
}
export -f curl

wget() {
  local argument
  local output_file=""

  printf '%s\n' "$*" >> "$DOWNLOAD_CALL_LOG"
  for argument in "$@"; do
    if [[ "$argument" == --output-document=* ]]; then
      output_file=${argument#--output-document=}
      break
    fi
  done

  [[ -n "$output_file" ]] || return 2
  printf '%s\n' "$MOCK_DOWNLOAD_CONTENT" > "$output_file"
}
export -f wget

prepare_restricted_path() {
  local utility
  local utility_path

  mkdir -p "$MOCK_BINARY_DIRECTORY"
  for utility in dirname mkdir mktemp rm chmod mv; do
    utility_path=$(command -v "$utility")
    ln -sf "$utility_path" "$MOCK_BINARY_DIRECTORY/$utility"
  done
}

prepare_case() {
  local case_name=$1

  CASE_DIRECTORY="$TEST_DIRECTORY/$case_name"
  DOCKER_CALL_LOG="$CASE_DIRECTORY/docker-calls.log"
  DOCKER_RUN_ARGS_LOG="$CASE_DIRECTORY/docker-run-args.log"
  DOWNLOAD_CALL_LOG="$CASE_DIRECTORY/download-calls.log"
  export DOCKER_CALL_LOG DOCKER_RUN_ARGS_LOG DOWNLOAD_CALL_LOG
  export MOCK_CURL_FAIL=false

  mkdir -p "$CASE_DIRECTORY"
  : > "$DOCKER_CALL_LOG"
  : > "$DOCKER_RUN_ARGS_LOG"
  : > "$DOWNLOAD_CALL_LOG"
}

run_script() {
  (cd "$CASE_DIRECTORY" && "$BASH" "$DOCKER_SCRIPT" "$@")
}

run_script_with_restricted_path() {
  (cd "$CASE_DIRECTORY" && PATH="$MOCK_BINARY_DIRECTORY" "$BASH" "$DOCKER_SCRIPT" "$@")
}

assert_success() {
  if ! COMMAND_OUTPUT=$(run_script "$@" 2>&1); then
    fail "$* failed unexpectedly: $COMMAND_OUTPUT"
  fi
}

assert_failure() {
  if COMMAND_OUTPUT=$(run_script "$@" 2>&1); then
    fail "$* succeeded unexpectedly"
  fi
}

assert_file_empty() {
  local file=$1

  [[ ! -s "$file" ]] || fail "expected $file to be empty"
}

assert_file_content() {
  local file=$1
  local expected=$2
  local actual

  [[ -f "$file" ]] || fail "expected $file to exist"
  actual=$(< "$file")
  [[ "$actual" == "$expected" ]] \
    || fail "unexpected content in $file: $actual"
}

assert_line_count() {
  local file=$1
  local expected=$2
  local actual=0

  while IFS= read -r _; do
    actual=$((actual + 1))
  done < "$file"

  [[ "$actual" -eq "$expected" ]] \
    || fail "expected $expected lines in $file, found $actual"
}

assert_run_args() {
  local -a actual=()
  local expected
  local index=0

  while IFS= read -r argument; do
    actual+=("$argument")
  done < "$DOCKER_RUN_ARGS_LOG"

  [[ "${#actual[@]}" -eq "$#" ]] \
    || fail "expected $# docker run arguments, found ${#actual[@]}: ${actual[*]}"

  for expected in "$@"; do
    [[ "${actual[$index]}" == "$expected" ]] \
      || fail "docker run argument $index: expected '$expected', found '${actual[$index]}'"
    index=$((index + 1))
  done
}

test_rejects_extra_arguments() {
  local option
  local command_name

  for option in --pull --start --stop --log --rm; do
    prepare_case "extra-argument-${option#--}"
    assert_failure "$option" unexpected
    command_name=${option#--}
    [[ "$COMMAND_OUTPUT" == *"$command_name: does not accept arguments: unexpected"* ]] \
      || fail "$option returned an unexpected error: $COMMAND_OUTPUT"
    assert_file_empty "$DOCKER_CALL_LOG"
  done
}

test_mainnet_defaults() {
  prepare_case mainnet-defaults
  assert_success --run

  assert_run_args \
    -d \
    --name tronprotocol-java-tron \
    -v "$CASE_DIRECTORY/output-directory:/java-tron/output-directory" \
    -p 127.0.0.1:8090:8090 \
    -p 127.0.0.1:50051:50051 \
    -p 18888:18888 \
    -p 18888:18888/udp \
    --restart always \
    tronprotocol/java-tron:latest \
    -c /java-tron/config.conf
  assert_file_empty "$DOWNLOAD_CALL_LOG"
}

test_custom_run_arguments() {
  local custom_volume="$TEST_DIRECTORY/data directory:/java-tron/output-directory"
  local custom_config="/config directory/custom.conf"

  prepare_case custom-run-arguments
  assert_success --run \
    -v "$custom_volume" \
    -p 127.0.0.1:18090:8090 \
    -c "$custom_config"

  assert_run_args \
    -d \
    --name tronprotocol-java-tron \
    -v "$custom_volume" \
    -p 127.0.0.1:18090:8090 \
    --restart always \
    tronprotocol/java-tron:latest \
    -c "$custom_config"
  assert_file_empty "$DOWNLOAD_CALL_LOG"
}

test_private_network_download() {
  local config_file

  prepare_case private-download
  config_file="$CASE_DIRECTORY/config/private_net_config.conf"
  assert_success --run --net private

  assert_file_content "$config_file" "$MOCK_DOWNLOAD_CONTENT"
  assert_line_count "$DOWNLOAD_CALL_LOG" 1
  assert_run_args \
    -d \
    --name tronprotocol-java-tron \
    -v "$CASE_DIRECTORY/output-directory:/java-tron/output-directory" \
    -v "$config_file:/java-tron/config.conf:ro" \
    -p 127.0.0.1:16667:16667 \
    -p 127.0.0.1:50051:50051 \
    -p 16666:16666 \
    -p 16666:16666/udp \
    --restart always \
    tronprotocol/java-tron:latest \
    -c /java-tron/config.conf \
    --witness
}

test_private_network_reuses_config() {
  local config_file

  prepare_case private-reuse
  config_file="$CASE_DIRECTORY/config/private_net_config.conf"
  mkdir -p "$(dirname "$config_file")"
  printf '%s\n' "user configuration" > "$config_file"

  assert_success --run --net private
  assert_file_content "$config_file" "user configuration"
  assert_file_empty "$DOWNLOAD_CALL_LOG"
}

test_private_network_updates_config() {
  local config_file

  prepare_case private-update
  config_file="$CASE_DIRECTORY/config/private_net_config.conf"
  mkdir -p "$(dirname "$config_file")"
  printf '%s\n' "old configuration" > "$config_file"

  assert_success --run --net private --update-config true
  assert_file_content "$config_file" "$MOCK_DOWNLOAD_CONTENT"
  assert_line_count "$DOWNLOAD_CALL_LOG" 1
}

test_private_network_download_failure() {
  local config_file

  prepare_case private-download-failure
  config_file="$CASE_DIRECTORY/config/private_net_config.conf"
  export MOCK_CURL_FAIL=true

  assert_failure --run --net private
  [[ "$COMMAND_OUTPUT" == *"failed to download private network configuration"* ]] \
    || fail "private download returned an unexpected error: $COMMAND_OUTPUT"
  [[ ! -e "$config_file" ]] || fail "failed download left $config_file behind"
  assert_file_empty "$DOCKER_CALL_LOG"
  assert_file_empty "$DOCKER_RUN_ARGS_LOG"
}

test_private_network_wget_fallback() {
  local config_file

  prepare_case private-wget-fallback
  prepare_restricted_path
  config_file="$CASE_DIRECTORY/config/private_net_config.conf"

  export -nf curl
  if ! COMMAND_OUTPUT=$(run_script_with_restricted_path --run --net private 2>&1); then
    export -f curl
    fail "wget fallback failed unexpectedly: $COMMAND_OUTPUT"
  fi
  export -f curl

  assert_file_content "$config_file" "$MOCK_DOWNLOAD_CONTENT"
  assert_line_count "$DOWNLOAD_CALL_LOG" 1
}

test_rejects_extra_arguments
test_mainnet_defaults
test_custom_run_arguments
test_private_network_download
test_private_network_reuses_config
test_private_network_updates_config
test_private_network_download_failure
test_private_network_wget_fallback

echo "docker.sh behavior tests passed"
