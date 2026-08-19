#!/bin/bash
#############################################################################
#
#                    GNU LESSER GENERAL PUBLIC LICENSE
#                        Version 3, 29 June 2007
#
#  Copyright (C) [2007] [TRON Foundation], Inc. <https://fsf.org/>
#  Everyone is permitted to copy and distribute verbatim copies
#  of this license document, but changing it is not allowed.
#
#
#   This version of the GNU Lesser General Public License incorporates
# the terms and conditions of version 3 of the GNU General Public
# License, supplemented by the additional permissions listed below.
#
# You can find java-tron at https://github.com/tronprotocol/java-tron/
#
##############################################################################

usage() {
  cat <<'EOF'
Usage: docker.sh COMMAND [OPTIONS]

Commands:
  --pull                         Pull the configured java-tron image
  --build [OPTIONS]              Build an image for the host architecture
  --run [OPTIONS]                Create and start a FullNode container
  --start                        Start the existing container
  --stop                         Stop the existing container
  --log                          Follow the java-tron log
  --rm                           Remove the existing container
  -h, --help                     Show this help message

Build options:
  --source local|remote          Build a host distribution or remote source
  --source-ref REF               Select a remote branch or tag
  --source-repository URL        Select a remote Git repository

Common options:
  --image NAME[:TAG]             Image for --pull, --build, or --run.
                                 JAVA_TRON_IMAGE can set the same value.
                                 Defaults: pull and run latest; build local.
  --container-name NAME          Container name for --run, --start, --stop,
                                 --log, and --rm. Default: tronprotocol-java-tron.

Run options:
  --net main|test|private        Select the network configuration
  --update-config true|false     Refresh the selected configuration
  --data-dir PATH                Set the host runtime-data directory
  --memory LIMIT                 Set the container memory limit
  --jvm-opts "OPTIONS"           Replace docker.sh default JVM options
  -p MAPPING                     Publish a container port; repeatable
  -v MAPPING                     Add or replace a bind mount; repeatable
  -e NAME=VALUE, --env NAME=VALUE
                                  Set an environment variable; repeatable.
                                  JVM option environment variables are not allowed;
                                  use --jvm-opts instead.
  -c CONTAINER_PATH              Use a custom configuration file
  -- [FULLNODE_ARGS...]          Pass remaining arguments to FullNode
EOF
}

if [ $# -eq 0 ]; then
  usage >&2
  exit 1
fi
if [[ "$1" = "-h" || "$1" = "--help" ]]; then
  usage
  exit 0
fi

BASE_DIR="/java-tron"
DOCKER_REPOSITORY="tronprotocol"
DOCKER_IMAGES="java-tron"
CONTAINER_NAME="$DOCKER_REPOSITORY-$DOCKER_IMAGES"
PULL_IMAGE_DEFAULT="$DOCKER_REPOSITORY/$DOCKER_IMAGES:latest"
BUILD_IMAGE_DEFAULT="$DOCKER_REPOSITORY/$DOCKER_IMAGES:local"
IMAGE_OVERRIDE="${JAVA_TRON_IMAGE:-}"

HOST_HTTP_PORT=8090
HOST_RPC_PORT=50051
HOST_LISTEN_PORT=18888
HOST_HTTP_BIND_ADDRESS="127.0.0.1"
HOST_RPC_BIND_ADDRESS="127.0.0.1"

DOCKER_HTTP_PORT=8090
DOCKER_RPC_PORT=50051
DOCKER_LISTEN_PORT=18888

DOCKER_MEMORY="16g"
JAVA_TRON_UID=10001
JAVA_TRON_GID=10001
# Helper-only defaults. The image and packaged vmoptions do not set heap size.
# JDK 8 images also receive -XX:MaxDirectMemorySize=1g at --run time.
JVM_OPTS="-Xms2g -XX:MaxRAMPercentage=60.0"

DEFAULT_DATA_DIR=$(pwd)

CONFIG_PATH="/java-tron/config/"
CONFIG_FILE="main_net_config.conf"
MAIN_NET_CONFIG_FILE="main_net_config.conf"
TEST_NET_CONFIG_FILE="test_net_config.conf"
PRIVATE_NET_CONFIG_FILE="private_net_config.conf"

# Preserve an existing configuration by default. A missing or empty file is
# downloaded for the initial run; use --update-config true to refresh it.
UPDATE_CONFIG=false

LOG_FILE="logs/tron.log"

JAVA_TRON_DOCKER_REPOSITORY="https://raw.githubusercontent.com/tronprotocol/java-tron/master/docker"
JAVA_TRON_SOURCE_REPOSITORY="https://github.com/tronprotocol/java-tron.git"
JAVA_TRON_SOURCE_REF="master"
CONFIG_REPOSITORY="https://raw.githubusercontent.com/tronprotocol/tron-deployment/master"
DOCKER_SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)

if ! command -v docker >/dev/null 2>&1; then
  echo "warning: docker must be installed, please install docker first."
  exit 1
fi
docker_version_output=$(docker --version) || exit 1
echo "$docker_version_output"
if [[ ! "$docker_version_output" =~ [Vv]ersion[[:space:]]+([0-9]+)\. ]]; then
  echo "Unable to determine the Docker version from: $docker_version_output" >&2
  exit 1
fi
if [ "${BASH_REMATCH[1]}" -lt 23 ]; then
  echo "Docker 23.0 or later is required for BuildKit target builds." >&2
  exit 1
fi

docker_ps() {
  if ! containerID=$(docker ps -aq --filter "name=^/${CONTAINER_NAME}$"); then
    echo "failed to query the java-tron container" >&2
    cid=""
    return 1
  fi
  cid=$containerID
}

valid_container_name() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]
}

set_container_name() {
  local command_name="$1"
  local value="$2"

  if ! valid_container_name "$value"; then
    echo "$command_name: invalid container name: $value" >&2
    return 1
  fi
  CONTAINER_NAME=$value
}

apply_container_name_args() {
  local command_name="$1"
  shift

  while [ $# -gt 0 ]; do
    case "$1" in
      --container-name)
        if [ $# -lt 2 ]; then
          echo "$command_name: arg $1 requires a value"
          return 1
        fi
        set_container_name "$command_name" "$2" || return 1
        shift 2
        ;;
      *)
        echo "$command_name: arg $1 is not a valid parameter"
        return 1
        ;;
    esac
  done
}

image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

selected_image() {
  if [ -n "$IMAGE_OVERRIDE" ]; then
    printf '%s\n' "$IMAGE_OVERRIDE"
    return
  fi

  case "$1" in
    pull|run)
      printf '%s\n' "$PULL_IMAGE_DEFAULT"
      ;;
    build)
      printf '%s\n' "$BUILD_IMAGE_DEFAULT"
      ;;
    *)
      echo "selected_image: unknown command $1" >&2
      return 1
      ;;
  esac
}

docker_image() {
  local ref

  ref=$(selected_image run) || return 1
  if [ -n "$ref" ] && image_exists "$ref"; then
    image=$ref
  else
    image=""
  fi
}

file_is_usable() {
  [ -f "$1" ] && [ -s "$1" ]
}

download_file() {
  local url="$1"
  local output="$2"
  local output_dir
  local temporary

  output_dir=$(dirname "$output")
  mkdir -p "$output_dir" || return 1
  temporary=$(mktemp "${output}.tmp.XXXXXX") || return 1

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL -o "$temporary" "$url"; then
      rm -f "$temporary"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q -O "$temporary" "$url"; then
      rm -f "$temporary"
      return 1
    fi
  else
    echo "Unable to download $url: install curl or wget first."
    rm -f "$temporary"
    return 1
  fi

  if [ ! -s "$temporary" ]; then
    echo "Downloaded file is empty: $url" >&2
    rm -f "$temporary"
    return 1
  fi

  if ! mv -f "$temporary" "$output"; then
    rm -f "$temporary"
    return 1
  fi
}

download_config() {
  local config_directory="$1"
  local config_file="$2"

  echo "Downloading $config_file"
  download_file "$CONFIG_REPOSITORY/$config_file" "$config_directory/$config_file"
}

check_download_config() {
  local config_directory="$1"
  local config_file="$2"

  if ! file_is_usable "$config_directory/$config_file"; then
    echo "$config_directory/$config_file is missing or empty; downloading it for the initial run."
    download_config "$config_directory" "$config_file"
  fi
}

has_port_mapping() {
  local expected_port="$1"
  local expected_protocol="$2"
  local mapping
  local container_spec
  local container_port
  local protocol
  shift 2

  for mapping in "$@"; do
    [ "$mapping" = "-p" ] && continue
    container_spec="${mapping##*:}"
    protocol="tcp"
    if [[ "$container_spec" == */* ]]; then
      protocol="${container_spec##*/}"
      container_spec="${container_spec%/*}"
    fi
    container_port="$container_spec"
    if [ "$container_port" = "$expected_port" ] && [ "$protocol" = "$expected_protocol" ]; then
      return 0
    fi
  done
  return 1
}

has_volume_mount() {
  local expected_target="$1"
  local mapping
  shift

  for mapping in "$@"; do
    [ "$mapping" = "-v" ] && continue
    if [[ "$mapping" == *":$expected_target" || "$mapping" == *":$expected_target:"* ]]; then
      return 0
    fi
  done
  return 1
}

image_architecture() {
  local image_ref="$1"

  docker image inspect -f '{{.Architecture}}' "$image_ref"
}

validate_image_user() {
  local image_ref="$1"
  local image_user

  if ! image_user=$(docker image inspect -f '{{.Config.User}}' "$image_ref"); then
    echo "run: failed to inspect image user: $image_ref" >&2
    return 1
  fi
  if [ "$image_user" != "$JAVA_TRON_UID:$JAVA_TRON_GID" ]; then
    echo "run: image $image_ref must run as UID:GID $JAVA_TRON_UID:$JAVA_TRON_GID; found '${image_user:-root}'" >&2
    echo "Pull or build an updated non-root java-tron image before retrying." >&2
    return 1
  fi
}

append_jdk8_direct_memory() {
  local image_ref="$1"
  local architecture

  if ! architecture=$(image_architecture "$image_ref"); then
    echo "run: failed to inspect image architecture: $image_ref" >&2
    return 1
  fi

  case "$architecture" in
    amd64|386)
      jvm_opts="$jvm_opts -XX:MaxDirectMemorySize=1g"
      ;;
  esac
}

prepare_runtime_directories() {
  local image_ref="$1"
  local host_directory
  local container_directory
  local first_entry
  local -a mount_args=()
  local -a host_directories=()
  local -a container_directories=()
  local -a initialize_directories=()
  shift

  while [ $# -gt 0 ]; do
    host_directory="$1"
    container_directory="$2"
    shift 2

    if [ -e "$host_directory" ] && [ ! -d "$host_directory" ]; then
      echo "run: runtime path is not a directory: $host_directory" >&2
      return 1
    fi
    mkdir -p "$host_directory" || return 1
    if ! first_entry=$(find "$host_directory" -mindepth 1 -maxdepth 1 -print -quit); then
      echo "run: failed to inspect runtime directory: $host_directory" >&2
      return 1
    fi

    mount_args+=("-v" "$host_directory:$container_directory")
    host_directories+=("$host_directory")
    container_directories+=("$container_directory")
    if [ -z "$first_entry" ]; then
      initialize_directories+=("$container_directory")
    fi
  done

  if [ ${#initialize_directories[@]} -gt 0 ]; then
    if ! docker run --rm \
      --user 0:0 \
      --security-opt no-new-privileges \
      --entrypoint chown \
      "${mount_args[@]}" \
      "$image_ref" \
      "$JAVA_TRON_UID:$JAVA_TRON_GID" \
      "${initialize_directories[@]}"; then
      echo "run: failed to initialize runtime-directory ownership" >&2
      return 1
    fi
  fi

  if docker run --rm \
    --security-opt no-new-privileges \
    --entrypoint sh \
    "${mount_args[@]}" \
    "$image_ref" \
    -ec '
      for path do
        test -w "$path"
        test -z "$(find "$path" -mindepth 1 -maxdepth 1 ! -writable -print -quit)"
      done
    ' sh "${container_directories[@]}"; then
    return 0
  fi

  echo "run: runtime directories must be writable by java-tron UID:GID $JAVA_TRON_UID:$JAVA_TRON_GID." >&2
  echo "Stop the node and migrate existing data before retrying:" >&2
  printf '  sudo chown -R %s:%s' "$JAVA_TRON_UID" "$JAVA_TRON_GID" >&2
  for host_directory in "${host_directories[@]}"; do
    printf ' %q' "$host_directory" >&2
  done
  printf '\n' >&2
  return 1
}

run() {
  local docker_memory="$DOCKER_MEMORY"
  local jvm_opts="$JVM_OPTS"
  local jvm_opts_replaced=false
  local data_dir="$DEFAULT_DATA_DIR"
  local config_directory
  local output_directory
  local logs_directory
  local env_name
  local -a volume_args=()
  local -a port_args=()
  local -a environment_args=()
  local -a tron_args=()
  local -a fullnode_args=()
  local -a default_runtime_directories=()
  local custom_config=false

  while [ $# -gt 0 ]; do
    case "$1" in
      -v)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        volume_args+=("-v" "$2")
        shift 2
        ;;
      -p)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        port_args+=("-p" "$2")
        shift 2
        ;;
      -e|--env)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        env_name="${2%%=*}"
        case "$env_name" in
          JAVA_OPTS|FULL_NODE_OPTS|JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS)
            echo "run: $1 $env_name is not supported; use --jvm-opts to set JVM options" >&2
            return 1
            ;;
        esac
        environment_args+=("--env" "$2")
        shift 2
        ;;
      -c)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        tron_args=("-c" "$2")
        UPDATE_CONFIG=false
        custom_config=true
        shift 2
        ;;
      --net)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        if [[ "$2" = "main" ]]; then
          CONFIG_FILE=$MAIN_NET_CONFIG_FILE
        elif [[ "$2" = "test" ]]; then
          CONFIG_FILE=$TEST_NET_CONFIG_FILE
        elif [[ "$2" = "private" ]]; then
          CONFIG_FILE=$PRIVATE_NET_CONFIG_FILE
        else
          echo "run: network $2 is not valid; expected main, test, or private"
          return 1
        fi
        shift 2
        ;;
      --update-config)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        if [[ "$2" != "true" && "$2" != "false" ]]; then
          echo "run: arg $1 must be true or false"
          return 1
        fi
        UPDATE_CONFIG=$2
        shift 2
        ;;
      --memory)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        docker_memory=$2
        shift 2
        ;;
      --data-dir)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        data_dir=$2
        shift 2
        ;;
      --jvm-opts)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        jvm_opts=$2
        jvm_opts_replaced=true
        shift 2
        ;;
      --image)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        IMAGE_OVERRIDE=$2
        shift 2
        ;;
      --container-name)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        set_container_name run "$2" || return 1
        shift 2
        ;;
      --)
        shift
        fullnode_args=("$@")
        break
        ;;
      *)
        echo "run: arg $1 is not a valid parameter"
        return 1
        ;;
    esac
  done

  docker_ps || return 1
  if [ -n "$cid" ]; then
    echo "container $CONTAINER_NAME already exists (ID: $cid)." >&2
    echo "Use --start to reuse it, or --rm before creating a new container." >&2
    return 1
  fi

  docker_image || return 1

  if [ -z "$image" ]; then
    if [ -n "$IMAGE_OVERRIDE" ]; then
      echo "run: image not found: $IMAGE_OVERRIDE" >&2
      return 1
    fi
    if [ ! -t 0 ]; then
      echo "run: no java-tron image found; pull one with --pull or build one with --build" >&2
      return 1
    fi

    echo 'warning: no java-tron mirror image, do you need to get the mirror image?[y/n]'
    read -r need

    if [[ $need == 'y' || $need == 'yes' ]]; then
      pull || return 1
      docker_image || return 1
      if [ -z "$image" ]; then
        echo "run: image is still unavailable after pull" >&2
        return 1
      fi
    else
      echo "warning: no mirror image found, go ahead and download a mirror."
      return 1
    fi
  fi

  validate_image_user "$image" || return 1

  if [[ "$data_dir" != /* ]]; then
    data_dir="$(pwd)/$data_dir"
  fi
  config_directory="$data_dir/config"
  output_directory="$data_dir/output-directory"
  logs_directory="$data_dir/logs"

  if [ "$custom_config" = false ]; then
    if [ "$UPDATE_CONFIG" = true ]; then
      download_config "$config_directory" "$CONFIG_FILE" || return 1
    else
      check_download_config "$config_directory" "$CONFIG_FILE" || return 1
    fi
  fi

  if ! has_volume_mount "/java-tron/config" "${volume_args[@]}"; then
    volume_args+=("-v" "$config_directory:/java-tron/config:ro")
  fi
  if ! has_volume_mount "/java-tron/output-directory" "${volume_args[@]}"; then
    default_runtime_directories+=("$output_directory" "/java-tron/output-directory")
    volume_args+=("-v" "$output_directory:/java-tron/output-directory")
  fi
  if ! has_volume_mount "/java-tron/logs" "${volume_args[@]}"; then
    default_runtime_directories+=("$logs_directory" "/java-tron/logs")
    volume_args+=("-v" "$logs_directory:/java-tron/logs")
  fi

  if [ ${#default_runtime_directories[@]} -gt 0 ]; then
    prepare_runtime_directories "$image" "${default_runtime_directories[@]}" || return 1
  fi

  if ! has_port_mapping "$DOCKER_HTTP_PORT" "tcp" "${port_args[@]}"; then
    port_args+=("-p" "$HOST_HTTP_BIND_ADDRESS:$HOST_HTTP_PORT:$DOCKER_HTTP_PORT")
  fi
  if ! has_port_mapping "$DOCKER_RPC_PORT" "tcp" "${port_args[@]}"; then
    port_args+=("-p" "$HOST_RPC_BIND_ADDRESS:$HOST_RPC_PORT:$DOCKER_RPC_PORT")
  fi
  if ! has_port_mapping "$DOCKER_LISTEN_PORT" "tcp" "${port_args[@]}"; then
    port_args+=("-p" "$HOST_LISTEN_PORT:$DOCKER_LISTEN_PORT")
  fi
  if ! has_port_mapping "$DOCKER_LISTEN_PORT" "udp" "${port_args[@]}"; then
    port_args+=("-p" "$HOST_LISTEN_PORT:$DOCKER_LISTEN_PORT/udp")
  fi

  if [ ${#tron_args[@]} -eq 0 ]; then
    tron_args=("-c" "$CONFIG_PATH$CONFIG_FILE")
  fi

  if [ "$jvm_opts_replaced" = false ]; then
    append_jdk8_direct_memory "$image" || return 1
  fi

  docker run -d --name "$CONTAINER_NAME" \
    --user "$JAVA_TRON_UID:$JAVA_TRON_GID" \
    "${volume_args[@]}" \
    "${port_args[@]}" \
    --memory "$docker_memory" \
    --env "JAVA_OPTS=$jvm_opts" \
    "${environment_args[@]}" \
    --security-opt no-new-privileges \
    --restart always \
    "$image" \
    "${tron_args[@]}" \
    "${fullnode_args[@]}"
}

build_local_image() (
  local source_root="$1"
  local dockerfile_path="$2"
  local distribution="$source_root/framework/build/distributions/java-tron-1.0.0.zip"
  local build_context

  if ! command -v unzip >/dev/null 2>&1; then
    echo "build: unzip is required for --source local" >&2
    return 1
  fi

  echo "Building the java-tron distribution from local source: $source_root"
  if ! (cd -- "$source_root" && ./gradlew :framework:distZip -x test -x check --no-daemon); then
    echo "build: failed to create the local java-tron distribution" >&2
    return 1
  fi
  if [ ! -f "$distribution" ]; then
    echo "build: expected distribution does not exist: $distribution" >&2
    return 1
  fi

  build_context=$(mktemp -d) || return 1
  trap 'rm -rf "$build_context"' EXIT

  if ! unzip -q -o "$distribution" -d "$build_context"; then
    echo "build: failed to extract $distribution" >&2
    return 1
  fi
  if [ ! -d "$build_context/java-tron-1.0.0" ]; then
    echo "build: the distribution does not contain java-tron-1.0.0" >&2
    return 1
  fi
  mv "$build_context/java-tron-1.0.0" "$build_context/java-tron" || return 1

  if [ ! -x "$build_context/java-tron/bin/FullNode" ] \
    || [ ! -f "$build_context/java-tron/bin/java-tron.vmoptions" ]; then
    echo "build: the staged distribution is missing FullNode or java-tron.vmoptions" >&2
    return 1
  fi

  download_file "$CONFIG_REPOSITORY/$MAIN_NET_CONFIG_FILE" \
    "$build_context/java-tron/config.conf" || return 1
  cp "$dockerfile_path" "$build_context/Dockerfile" || return 1

  echo "Building the local image from a temporary distribution-only context."
  DOCKER_BUILDKIT=1 docker build \
    --target local \
    --file "$build_context/Dockerfile" \
    -t "$(selected_image build)" \
    "$build_context"
)

build_remote_image() (
  local dockerfile_path="$1"
  local source_repository="$2"
  local source_ref="$3"
  local build_context

  build_context=$(mktemp -d) || return 1
  trap 'rm -rf "$build_context"' EXIT
  cp "$dockerfile_path" "$build_context/Dockerfile" || return 1

  echo "Building remote java-tron source '$source_ref' from $source_repository."
  echo "Local working-tree changes are not included; use --source local to include them."
  DOCKER_BUILDKIT=1 docker build \
    --target remote \
    --file "$build_context/Dockerfile" \
    --build-arg "SOURCE_REPOSITORY=$source_repository" \
    --build-arg "SOURCE_REF=$source_ref" \
    -t "$(selected_image build)" \
    "$build_context"
)

build() {
  local architecture
  local dockerfile_path
  local dockerfile_relative
  local script_dir
  local source_root
  local source_mode="remote"
  local source_ref="$JAVA_TRON_SOURCE_REF"
  local source_repository="$JAVA_TRON_SOURCE_REPOSITORY"
  local source_ref_set=false
  local source_repository_set=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --source)
        if [ $# -lt 2 ]; then
          echo "build: arg $1 requires a value"
          return 1
        fi
        if [[ "$2" != "local" && "$2" != "remote" ]]; then
          echo "build: source $2 is not valid; expected local or remote"
          return 1
        fi
        source_mode=$2
        shift 2
        ;;
      --source-ref)
        if [ $# -lt 2 ]; then
          echo "build: arg $1 requires a value"
          return 1
        fi
        source_ref=$2
        source_ref_set=true
        shift 2
        ;;
      --source-repository)
        if [ $# -lt 2 ]; then
          echo "build: arg $1 requires a value"
          return 1
        fi
        source_repository=$2
        source_repository_set=true
        shift 2
        ;;
      --image)
        if [ $# -lt 2 ]; then
          echo "build: arg $1 requires a value"
          return 1
        fi
        IMAGE_OVERRIDE=$2
        shift 2
        ;;
      *)
        echo "build: arg $1 is not a valid parameter"
        return 1
        ;;
    esac
  done

  if [ "$source_mode" = "local" ] && { [ "$source_ref_set" = true ] || [ "$source_repository_set" = true ]; }; then
    echo "build: --source-ref and --source-repository can only be used with --source remote"
    return 1
  fi

  script_dir=$DOCKER_SCRIPT_DIR
  architecture=$(uname -m)
  case "$architecture" in
    x86_64|amd64)
      dockerfile_relative="Dockerfile"
      ;;
    arm64|aarch64)
      dockerfile_relative="arm64/Dockerfile"
      ;;
    *)
      echo "Unsupported architecture: $architecture; expected x86_64, amd64, arm64, or aarch64."
      return 1
      ;;
  esac

  if [ "$source_mode" = "local" ]; then
    if [ -x "$(pwd)/gradlew" ]; then
      source_root=$(pwd)
    elif [ -x "$script_dir/gradlew" ]; then
      source_root=$script_dir
    elif [ -x "$script_dir/../gradlew" ]; then
      source_root=$(cd -- "$script_dir/.." >/dev/null 2>&1 && pwd)
    else
      echo "build: unable to find a java-tron checkout for local source"
      echo "Run this command from the repository root or use docker/docker.sh from a checkout."
      return 1
    fi

    dockerfile_path="$source_root/docker/$dockerfile_relative"
    if ! file_is_usable "$dockerfile_path"; then
      echo "build: local Dockerfile does not exist: $dockerfile_path" >&2
      return 1
    fi
    build_local_image "$source_root" "$dockerfile_path"
  else
    dockerfile_path="$script_dir/$dockerfile_relative"
    if ! file_is_usable "$dockerfile_path"; then
      echo "$dockerfile_relative does not exist; downloading it."
      download_file "$JAVA_TRON_DOCKER_REPOSITORY/$dockerfile_relative" "$dockerfile_path" || return 1
    fi
    build_remote_image "$dockerfile_path" "$source_repository" "$source_ref"
  fi
}

pull() {
  local image_name

  while [ $# -gt 0 ]; do
    case "$1" in
      --image)
        if [ $# -lt 2 ]; then
          echo "pull: arg $1 requires a value"
          return 1
        fi
        IMAGE_OVERRIDE=$2
        shift 2
        ;;
      *)
        echo "pull: arg $1 is not a valid parameter"
        return 1
        ;;
    esac
  done

  image_name=$(selected_image pull) || return 1
  echo "docker pull $image_name"
  docker pull "$image_name"
}

start() {
  apply_container_name_args start "$@" || return 1
  docker_ps || return 1
  if [ -n "$cid" ]; then
    echo "containerID: $cid"
    echo "docker start $cid"
    docker start "$cid" || return 1
    docker ps || return 1
  else
    echo "container does not exist!" >&2
    return 1
  fi
}

stop() {
  apply_container_name_args stop "$@" || return 1
  docker_ps || return 1
  if [ -n "$cid" ]; then
    echo "containerID: $cid"
    echo "docker stop $cid"
    docker stop "$cid" || return 1
    docker ps || return 1
  else
    echo "container does not exist!" >&2
    return 1
  fi
}

rm_container() {
  apply_container_name_args rm "$@" || return 1
  stop || return 1
  echo "containerID: $cid"
  echo "docker rm $cid"
  docker rm "$cid" || return 1
  docker_ps || return 1
}

log() {
  apply_container_name_args log "$@" || return 1
  docker_ps || return 1

  if [ -n "$cid" ]; then
    echo "containerID: $cid"
    docker exec "$cid" tail -100f "$BASE_DIR/$LOG_FILE" || return 1
  else
    echo "container does not exist!" >&2
    return 1
  fi

}

case "$1" in
  --pull)
    pull "${@:2}"
    exit
    ;;
  --start)
    start "${@:2}"
    exit
    ;;
  --stop)
    stop "${@:2}"
    exit
    ;;
  --build)
    build "${@:2}"
    exit
    ;;
  --run)
    run "${@:2}"
    exit
    ;;
  --rm)
    rm_container "${@:2}"
    exit
    ;;
  --log)
    log "${@:2}"
    exit
    ;;
  *)
    echo "arg: $1 is not a valid parameter"
    exit 1
    ;;
esac
