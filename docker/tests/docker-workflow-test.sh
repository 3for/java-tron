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

echo "Docker CI config.conf selection test passed"
