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

BASE_DIR="/java-tron"
DOCKER_REPOSITORY="tronprotocol"
DOCKER_IMAGES="java-tron"
# latest or version
DOCKER_TARGET="latest"

HOST_HTTP_PORT=8090
HOST_RPC_PORT=50051
HOST_LISTEN_PORT=18888
HOST_HTTP_BIND_ADDRESS="127.0.0.1"
HOST_RPC_BIND_ADDRESS="127.0.0.1"

DOCKER_HTTP_PORT=8090
DOCKER_RPC_PORT=50051
DOCKER_LISTEN_PORT=18888

DOCKER_MEMORY="16g"
JVM_OPTS="-Xms2g -XX:MaxRAMPercentage=60.0 -XX:MaxDirectMemorySize=1g"

VOLUME=$(pwd)
CONFIG="$VOLUME/config"
OUTPUT_DIRECTORY="$VOLUME/output-directory"

CONFIG_PATH="/java-tron/config/"
CONFIG_FILE="main_net_config.conf"
MAIN_NET_CONFIG_FILE="main_net_config.conf"
TEST_NET_CONFIG_FILE="test_net_config.conf"
PRIVATE_NET_CONFIG_FILE="private_net_config.conf"

# update the configuration file, if true, the configuration file will be fetched from the network every time you start
UPDATE_CONFIG=true

LOG_FILE="logs/tron.log"

JAVA_TRON_DOCKER_REPOSITORY="https://raw.githubusercontent.com/tronprotocol/java-tron/develop/docker"
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
  if ! containerID=$(docker ps -aq --filter "name=^/$DOCKER_REPOSITORY-$DOCKER_IMAGES$"); then
    echo "failed to query the java-tron container" >&2
    cid=""
    return 1
  fi
  cid=$containerID
}

docker_image() {
  if docker image inspect "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" >/dev/null 2>&1; then
    image="$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET"
  else
    image=""
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  mkdir -p "$(dirname "$output")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$output" "$url"
  else
    echo "Unable to download $url: install curl or wget first."
    return 1
  fi
}

download_config() {
  echo "Downloading $CONFIG_FILE"
  download_file "$CONFIG_REPOSITORY/$CONFIG_FILE" "$CONFIG/$CONFIG_FILE"
}

check_download_config() {
  if [ ! -f "$CONFIG/$CONFIG_FILE" ]; then
    echo "$CONFIG/$CONFIG_FILE does not exist; downloading it for the initial run."
    download_config
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

run() {
  docker_image

  if [ -z "$image" ]; then
    echo 'warning: no java-tron mirror image, do you need to get the mirror image?[y/n]'
    read -r need

    if [[ $need == 'y' || $need == 'yes' ]]; then
      pull
    else
      echo "warning: no mirror image found, go ahead and download a mirror."
      return 1
    fi
  fi

  local docker_memory="$DOCKER_MEMORY"
  local jvm_opts="$JVM_OPTS"
  local -a volume_args=()
  local -a port_args=()
  local -a environment_args=()
  local -a tron_args=()
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
      --jvm-opts)
        if [ $# -lt 2 ]; then
          echo "run: arg $1 requires a value"
          return 1
        fi
        jvm_opts=$2
        shift 2
        ;;
      *)
        echo "run: arg $1 is not a valid parameter"
        return 1
        ;;
    esac
  done

  if [ "$custom_config" = false ]; then
    if [ "$UPDATE_CONFIG" = true ]; then
      download_config || return 1
    else
      check_download_config || return 1
    fi
  fi

  if ! has_volume_mount "/java-tron/config" "${volume_args[@]}"; then
    volume_args+=("-v" "$CONFIG:/java-tron/config")
  fi
  if ! has_volume_mount "/java-tron/output-directory" "${volume_args[@]}"; then
    volume_args+=("-v" "$OUTPUT_DIRECTORY:/java-tron/output-directory")
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

  docker run -d -it --name "$DOCKER_REPOSITORY-$DOCKER_IMAGES" \
    "${volume_args[@]}" \
    "${port_args[@]}" \
    --memory "$docker_memory" \
    --env "JAVA_OPTS=$jvm_opts" \
    "${environment_args[@]}" \
    --restart always \
    "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" \
    "${tron_args[@]}"
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
    -t "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" \
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
    -t "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" \
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

  dockerfile_path="$script_dir/$dockerfile_relative"
  if [ ! -f "$dockerfile_path" ]; then
    echo "$dockerfile_relative does not exist; downloading it."
    download_file "$JAVA_TRON_DOCKER_REPOSITORY/$dockerfile_relative" "$dockerfile_path" || return 1
  fi

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
    build_local_image "$source_root" "$dockerfile_path"
  else
    build_remote_image "$dockerfile_path" "$source_repository" "$source_ref"
  fi
}

pull() {
  echo "docker pull $DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET"
  docker pull "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET"
}

start() {
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
  stop || return 1
  echo "containerID: $cid"
  echo "docker rm $cid"
  docker rm "$cid" || return 1
  docker_ps || return 1
}

log() {
  docker_ps || return 1

  if [ -n "$cid" ]; then
    echo "containerID: $cid"
    docker exec -it "$cid" tail -100f "$BASE_DIR/$LOG_FILE" || return 1
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
