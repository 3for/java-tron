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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/java-tron"
DOCKER_REPOSITORY="tronprotocol"
DOCKER_IMAGES="java-tron"
# latest or version
DOCKER_TARGET="latest"

HOST_HTTP_PORT=8090
HOST_RPC_PORT=50051
HOST_LISTEN_PORT=18888

DOCKER_HTTP_PORT=8090
DOCKER_RPC_PORT=50051
DOCKER_LISTEN_PORT=18888

VOLUME=`pwd`
CONFIG_DIR="$VOLUME/config"
OUTPUT_DIRECTORY="$VOLUME/output-directory"

BUNDLED_CONFIG_FILE="$BASE_DIR/config.conf"
PRIVATE_NET_CONFIG_FILE="private_net_config.conf"
PRIVATE_NET_CONFIG_URL="https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/$PRIVATE_NET_CONFIG_FILE"

LOG_FILE="/logs/tron.log"

JAVA_TRON_DOCKER_URL="https://raw.githubusercontent.com/tronprotocol/java-tron/develop/docker"

if test docker; then
  docker -v
else
  echo "warning: docker must be installed, please install docker first."
  exit
fi

docker_ps() {
  containerID=`docker ps -a | grep "$DOCKER_REPOSITORY-$DOCKER_IMAGES" | awk '{print $1}'`
  cid=$containerID
}

docker_image() {
  image_name=`docker images |grep "$DOCKER_REPOSITORY/$DOCKER_IMAGES" |awk {'print $1'}| awk 'NR==1'`
  image=$image_name
}

download_build_file() {
  local source_url=$1
  local destination=$2

  if command -v curl >/dev/null 2>&1; then
    if ! curl --fail --silent --show-error --location \
        --output "$destination" "$source_url"; then
      echo "build: failed to download: $source_url" >&2
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget --quiet --output-document="$destination" "$source_url"; then
      echo "build: failed to download: $source_url" >&2
      return 1
    fi
  else
    echo "build: curl or wget is required to download build files" >&2
    return 1
  fi

  if [[ ! -s "$destination" ]]; then
    echo "build: downloaded file is empty: $source_url" >&2
    return 1
  fi
}

download_private_config() {
  local config_file=$1
  local temp_file

  if ! mkdir -p "$CONFIG_DIR"; then
    echo "run: failed to create configuration directory: $CONFIG_DIR"
    return 1
  fi

  if ! temp_file=$(mktemp "$CONFIG_DIR/.private_net_config.conf.XXXXXX"); then
    echo "run: failed to create a temporary configuration file"
    return 1
  fi

  if command -v curl >/dev/null 2>&1; then
    if ! curl --fail --silent --show-error --location \
        --output "$temp_file" "$PRIVATE_NET_CONFIG_URL"; then
      rm -f "$temp_file"
      echo "run: failed to download private network configuration"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget --quiet --output-document="$temp_file" "$PRIVATE_NET_CONFIG_URL"; then
      rm -f "$temp_file"
      echo "run: failed to download private network configuration"
      return 1
    fi
  else
    rm -f "$temp_file"
    echo "run: curl or wget is required to download the private network configuration"
    return 1
  fi

  if [[ ! -s "$temp_file" ]]; then
    rm -f "$temp_file"
    echo "run: downloaded private network configuration is empty"
    return 1
  fi

  chmod 644 "$temp_file"
  if ! mv -f "$temp_file" "$config_file"; then
    rm -f "$temp_file"
    echo "run: failed to save private network configuration: $config_file"
    return 1
  fi

  echo "private network configuration saved to $config_file"
}

run() {
  docker_image

  if [ ! $image ] ; then
    echo 'warning: no java-tron mirror image, do you need to get the mirror image?[y/n]'
    read need

    if [[ $need == 'y' || $need == 'yes' ]]; then
      pull
    else
      echo "warning: no mirror image found, go ahead and download a mirror."
      exit
    fi
  fi

  volume=""
  parameter=""
  tron_parameter=""
  network="main"
  network_config=""
  custom_config=false
  update_config=false
  if [ $# -gt 0 ]; then
    while [ -n "$1" ]; do
      case "$1" in
        -v)
          volume="$volume -v $2"
          shift 2
          ;;
        -p)
          parameter="$parameter -p $2"
          shift 2
          ;;
        -c)
          tron_parameter="$tron_parameter -c $2"
          custom_config=true
          shift 2
          ;;
        --net)
          network=$2
          shift 2
          ;;
        --update-config)
          if [[ "$2" != "true" && "$2" != "false" ]]; then
            echo "run: --update-config expects true or false"
            exit 1
          fi
          update_config=$2
          shift 2
          ;;
        *)
          echo "run: arg $1 is not a valid parameter"
          exit
          ;;
      esac
    done

    if [[ "$network" = "private" ]]; then
      network_config="$CONFIG_DIR/$PRIVATE_NET_CONFIG_FILE"
    elif [[ "$network" != "main" ]]; then
      echo "run: unsupported network '$network'; expected main or private"
      exit 1
    fi

    if [[ "$custom_config" = true && -n "$network_config" ]]; then
      echo "run: -c cannot be combined with --net private"
      exit 1
    fi

    if [[ "$update_config" = true && "$network" != "private" ]]; then
      echo "run: --update-config true is only supported with --net private"
      exit 1
    fi

    if [[ -n "$network_config" ]]; then
      if [[ "$update_config" = true ]]; then
        echo "updating private network configuration from tron-deployment"
        download_private_config "$network_config" || exit 1
      elif [[ ! -f "$network_config" ]]; then
        echo "private network configuration not found; downloading it from tron-deployment"
        download_private_config "$network_config" || exit 1
      fi
      volume="$volume -v $network_config:$BUNDLED_CONFIG_FILE:ro"
    fi

    if [[ "$volume" != *":/java-tron/output-directory"* ]]; then
      volume=" -v $OUTPUT_DIRECTORY:/java-tron/output-directory$volume"
    fi

    if [ -z "$parameter" ]; then
      parameter=" -p $HOST_HTTP_PORT:$DOCKER_HTTP_PORT -p $HOST_RPC_PORT:$DOCKER_RPC_PORT -p $HOST_LISTEN_PORT:$DOCKER_LISTEN_PORT"
    fi

    if [ -z "$tron_parameter" ]; then
      tron_parameter=" -c $BUNDLED_CONFIG_FILE"
    fi

    # Using custom parameters
    docker run -d -it --name "$DOCKER_REPOSITORY-$DOCKER_IMAGES" \
        $volume \
        $parameter \
        --restart always \
        "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" \
        $tron_parameter
  else
    # Default parameters
    docker run -d -it --name "$DOCKER_REPOSITORY-$DOCKER_IMAGES" \
      -v $OUTPUT_DIRECTORY:/java-tron/output-directory \
      -p $HOST_HTTP_PORT:$DOCKER_HTTP_PORT \
      -p $HOST_RPC_PORT:$DOCKER_RPC_PORT \
      -p $HOST_LISTEN_PORT:$DOCKER_LISTEN_PORT \
      --restart always \
      "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" \
      -c "$BUNDLED_CONFIG_FILE"
  fi
}

build() {
  local arch="${1:-}"
  local platform
  local dockerfile_path
  local dockerfile_source
  local build_context="$SCRIPT_DIR"
  local temporary_context=""
  local build_status

  if [[ $# -gt 1 ]]; then
    echo "build: expected at most one architecture argument" >&2
    return 1
  fi

  if [[ -z "$arch" ]]; then
    if ! arch=$(docker info --format '{{.Architecture}}'); then
      echo "build: failed to determine the Docker daemon architecture" >&2
      return 1
    fi
  fi

  case "$arch" in
    amd64 | x86_64)
      platform="linux/amd64"
      dockerfile_path="$SCRIPT_DIR/Dockerfile"
      dockerfile_source="$JAVA_TRON_DOCKER_URL/Dockerfile"
      ;;
    arm64 | aarch64)
      platform="linux/arm64"
      dockerfile_path="$SCRIPT_DIR/arm64/Dockerfile"
      dockerfile_source="$JAVA_TRON_DOCKER_URL/arm64/Dockerfile"
      ;;
    *)
      echo "build: unsupported architecture: $arch" >&2
      return 1
      ;;
  esac

  if [[ ! -f "$dockerfile_path" || ! -f "$SCRIPT_DIR/docker-entrypoint.sh" ]]; then
    if ! temporary_context=$(mktemp -d "${TMPDIR:-/tmp}/java-tron-docker.XXXXXX"); then
      echo "build: failed to create a temporary build context" >&2
      return 1
    fi

    build_context="$temporary_context"
    dockerfile_path="$temporary_context/Dockerfile"

    echo "build files not found next to docker.sh; downloading a temporary build context"
    if ! download_build_file "$dockerfile_source" "$dockerfile_path" \
        || ! download_build_file "$JAVA_TRON_DOCKER_URL/docker-entrypoint.sh" \
          "$temporary_context/docker-entrypoint.sh"; then
      rm -rf "$temporary_context"
      return 1
    fi
    chmod 755 "$temporary_context/docker-entrypoint.sh"
  fi

  echo "docker build --platform $platform --file $dockerfile_path"
  docker build \
    --platform "$platform" \
    --file "$dockerfile_path" \
    --tag "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" \
    "$build_context"
  build_status=$?

  if [[ -n "$temporary_context" ]]; then
    rm -rf "$temporary_context"
  fi

  return "$build_status"
}

pull() {
  echo "docker pull $DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET"
  docker pull "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET"
}

start() {
  docker_ps
  if [ $cid ]; then
    echo "containerID: $cid"
    echo "docker stop $cid"
    docker start $cid
    docker ps
  else
    echo "container not running!"
  fi
}

stop() {
  docker_ps
  if [ $cid ]; then
    echo "containerID: $cid"
    echo "docker stop $cid"
    docker stop $cid
    docker ps
  else
    echo "container not running!"
  fi
}

rm_container() {
  stop
  if [ $cid ]; then
    echo "containerID: $cid"
    echo "docker rm $cid"
    docker rm $cid
    docker_ps
  else
    echo "image not exists!"
  fi
}

log() {
  docker_ps

  if [ $cid ]; then
    echo "containerID: $cid"
    docker exec -it $cid tail -100f $BASE_DIR/$LOG_FILE
  else
    echo "container not exists!"
  fi

}

case "$1" in
  --pull)
    pull ${@: 2}
    exit
    ;;
  --start)
    start ${@: 2}
    exit
    ;;
  --stop)
    stop ${@: 2}
    exit
    ;;
  --build)
    build "${@:2}"
    exit
    ;;
  --run)
    run ${@: 2}
    exit
    ;;
  --rm)
    rm_container ${@: 2}
    exit
    ;;
  --log)
    log ${@: 2}
    exit
    ;;
  *)
    echo "arg: $1 is not a valid parameter"
    exit
    ;;
esac
