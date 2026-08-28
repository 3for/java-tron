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

JAVA_TRON_REPOSITORY="https://raw.githubusercontent.com/tronprotocol/java-tron/develop/"
DOCKER_FILE="Dockerfile"
ENDPOINT_SHELL="docker-entrypoint.sh"

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
  echo 'docker build'
  if [ ! -f "Dockerfile" ]; then
    echo 'warning: Dockerfile not exists.'
    if test curl; then
      DOWNLOAD_CMD="curl -LJO "
    elif test wget; then
      DOWNLOAD_CMD="wget "
    else
      echo "Dockerfile cannot be downloaded, you need to install 'curl' or 'wget'!"
      exit
    fi
    # download Dockerfile
   `$DOWNLOAD_CMD "$JAVA_TRON_REPOSITORY$DOCKER_FILE"`
   `$DOWNLOAD_CMD "$JAVA_TRON_REPOSITORY$ENDPOINT_SHELL"`
   chmod u+rwx $ENDPOINT_SHELL
  fi
  docker build -t "$DOCKER_REPOSITORY/$DOCKER_IMAGES:$DOCKER_TARGET" .
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
    build ${@: 2}
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
