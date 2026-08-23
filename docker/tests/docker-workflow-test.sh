#!/bin/bash
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
repository_root=$(cd -- "$test_dir/../.." >/dev/null 2>&1 && pwd)
workflow="$repository_root/.github/workflows/docker.yml"
config_path="framework/src/main/resources/config.conf"

if [ "$(grep -Fxc -- "      - '$config_path'" "$workflow" || true)" -ne 1 ]; then
  echo "Docker CI push paths do not include $config_path exactly once." >&2
  exit 1
fi

if ! grep -Eq -- "^[[:space:]]+.*${config_path//./\\.}.*\\)$" "$workflow"; then
  echo "Docker CI's pull-request selector does not rebuild images for $config_path." >&2
  exit 1
fi

assert_job_needs_changes_only() {
  local job="$1"

  if ! awk -v job="$job" '
    $0 == "  " job ":" { in_job = 1; next }
    in_job && /^  [^[:space:]]/ { exit }
    in_job && $0 == "    needs: changes" { found = 1 }
    END { exit !found }
  ' "$workflow"; then
    echo "Docker CI job $job must depend only on change analysis." >&2
    exit 1
  fi
}

assert_job_needs_changes_only build-amd64
assert_job_needs_changes_only build-arm64

if [ "$(grep -Fxc -- '        uses: docker/setup-buildx-action@v4' "$workflow" || true)" -ne 2 ]; then
  echo "Both architecture jobs must set up the official Docker Buildx action." >&2
  exit 1
fi
if [ "$(grep -Fxc -- '        uses: docker/build-push-action@v7' "$workflow" || true)" -ne 4 ]; then
  echo "Local and remote builds for both architectures must use build-push-action." >&2
  exit 1
fi
if [ "$(grep -Fc -- 'cache-from: type=gha,scope=java-tron-' "$workflow" || true)" -ne 4 ] \
  || [ "$(grep -Fc -- 'cache-to: type=gha,mode=max,scope=java-tron-' "$workflow" || true)" -ne 4 ]; then
  echo "Each local and remote architecture build must use an isolated GHA cache scope." >&2
  exit 1
fi
if [ "$(grep -Fxc -- '          no-cache-filters: remote-builder' "$workflow" || true)" -ne 2 ]; then
  echo "Remote builds must bypass cache for the mutable source-builder stage." >&2
  exit 1
fi

echo "Docker CI selection, parallelism, and Buildx cache tests passed"
