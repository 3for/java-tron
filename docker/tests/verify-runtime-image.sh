#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 IMAGE JAVA_VERSION_REGEX" >&2
  exit 1
fi

image=$1
java_version_regex=$2
test_dir=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
repository_root=$(cd -- "$test_dir/../.." >/dev/null 2>&1 && pwd)
invoking_uid=$(id -u)
invoking_gid=$(id -g)

test "$(docker image inspect --format '{{.Config.User}}' "$image")" = "10001:10001"

docker run --rm --entrypoint sh "$image" -ec '
  set -eu

  test "$(id -u)" = 10001
  test "$(id -g)" = 10001
  test -x /java-tron/bin/FullNode
  test -f /java-tron/bin/java-tron.vmoptions
  test -f /java-tron/config.conf
  test -d /java-tron/output-directory
  test -d /java-tron/logs

  test "$(stat -c %u:%g /java-tron)" = "0:0"
  test "$(stat -c %u:%g /java-tron/bin)" = "0:0"
  test "$(stat -c %u:%g /java-tron/bin/FullNode)" = "0:0"
  test "$(stat -c %u:%g /java-tron/bin/java-tron.vmoptions)" = "0:0"
  test "$(stat -c %u:%g /java-tron/config.conf)" = "0:0"
  lib_jar=$(find /java-tron/lib -maxdepth 1 -type f -name "*.jar" -print -quit)
  test -n "$lib_jar"
  test "$(stat -c %u:%g "$lib_jar")" = "0:0"
  test "$(stat -c %u:%g /java-tron/output-directory)" = "10001:10001"
  test "$(stat -c %u:%g /java-tron/logs)" = "10001:10001"

  test ! -w /java-tron
  test ! -w /java-tron/bin
  test ! -w /java-tron/bin/FullNode
  test ! -w /java-tron/bin/java-tron.vmoptions
  test ! -w /java-tron/config.conf
  test ! -w "$lib_jar"
  test -w /java-tron/output-directory
  test -w /java-tron/logs
  ! touch /java-tron/.write-test

  grep -Eq -- "-Xloggc:/java-tron/logs/gc.log|:file=/java-tron/logs/gc.log:" \
    /java-tron/bin/java-tron.vmoptions
  grep -Fq -- "-XX:HeapDumpPath=/java-tron/logs" /java-tron/bin/java-tron.vmoptions
  grep -Fq -- "-XX:ErrorFile=/java-tron/logs/hs_err_pid%p.log" \
    /java-tron/bin/java-tron.vmoptions
  ! grep -Eq -- "-Xloggc:./gc.log|:file=gc.log:" /java-tron/bin/java-tron.vmoptions
'

runtime_dir=$(mktemp -d "$repository_root/.verify-runtime-image.XXXXXX")

cleanup() {
  local test_status=$?
  local cleanup_status=0

  trap - EXIT
  set +e

  if [ -d "$runtime_dir" ]; then
    if ! docker run --rm \
      --user 0:0 \
      --network none \
      --read-only \
      --security-opt no-new-privileges \
      --cap-drop ALL \
      --cap-add CHOWN \
      --cap-add DAC_READ_SEARCH \
      --entrypoint chown \
      --mount "type=bind,src=$runtime_dir,dst=/cleanup" \
      "$image" -R "$invoking_uid:$invoking_gid" /cleanup; then
      echo "Failed to restore runtime-test directory ownership: $runtime_dir" >&2
      cleanup_status=1
    fi

    if ! rm -rf -- "$runtime_dir"; then
      echo "Failed to remove runtime-test directory: $runtime_dir" >&2
      cleanup_status=1
    fi
  fi

  if [ "$test_status" -eq 0 ] && [ "$cleanup_status" -ne 0 ]; then
    test_status=$cleanup_status
  fi
  exit "$test_status"
}
trap cleanup EXIT

mkdir -p "$runtime_dir/output-directory" "$runtime_dir/logs"
docker run --rm \
  --user 0:0 \
  --network none \
  --read-only \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add DAC_READ_SEARCH \
  --entrypoint chown \
  -v "$runtime_dir/output-directory:/java-tron/output-directory" \
  -v "$runtime_dir/logs:/java-tron/logs" \
  "$image" 10001:10001 /java-tron/output-directory /java-tron/logs
docker run --rm --security-opt no-new-privileges --entrypoint sh \
  -v "$runtime_dir/output-directory:/java-tron/output-directory" \
  -v "$runtime_dir/logs:/java-tron/logs" \
  "$image" -ec '
    grep -Eq "^NoNewPrivs:[[:space:]]+1$" /proc/self/status
    touch /java-tron/output-directory/.write-test
    touch /java-tron/logs/.write-test
  '
test -f "$runtime_dir/output-directory/.write-test"
test -f "$runtime_dir/logs/.write-test"

version=$(docker run --rm --entrypoint java "$image" -version 2>&1)
echo "$version"
grep -Eq "$java_version_regex" <<< "$version"
