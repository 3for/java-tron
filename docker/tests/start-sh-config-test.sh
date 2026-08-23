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
  /^(downloadTo\(\) \{|specifyConfig\(\)\{)$/ { capture = 1 }
  capture { print }
  capture && /^}$/ { capture = 0 }
' "$START_SCRIPT")
eval "$function_source"

if ! declare -F specifyConfig >/dev/null || ! declare -F downloadTo >/dev/null; then
  echo "Failed to load the configuration functions from start.sh" >&2
  exit 1
fi

downloadTo() {
  local url="$1"
  local output="$2"

  printf '%s|%s\n' "$url" "$output" >> "$DOWNLOAD_LOG"
  printf 'downloaded private configuration\n' > "$output"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$actual" != "$expected" ]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

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

echo "start.sh private configuration tests passed"
