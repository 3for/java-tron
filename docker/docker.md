# Docker Shell Guide

java-tron supports containerized processes. We maintain a Docker image built from the latest version of the `master` branch on Docker Hub. The `docker.sh` helper simplifies common image and container lifecycle operations.

## Prerequisites

Install Docker 20.10.12 or later before using the helper.

## Quick Start

Obtain the helper from the java-tron repository, or download it independently:

```shell
$ wget https://raw.githubusercontent.com/tronprotocol/java-tron/develop/docker/docker.sh
```

### Pull the mirror image

Get the `tronprotocol/java-tron` image from Docker Hub. The image contains a Java runtime environment and the mainnet configuration file.

```shell
$ bash docker.sh --pull
```

### Run the service

Before running java-tron, make sure the required ports are available on the host. By default, `docker.sh --run` publishes the following container ports:

- `8090`: used by the HTTP-based JSON API
- `50051`: used by the gRPC-based API
- `18888`: TCP and UDP, used by the P2P protocol running the network

#### Full node on the main network

```shell
$ bash docker.sh --run
```

The mainnet configuration is bundled in the image at `/java-tron/config.conf` and comes from the same java-tron revision used to build the image. `--net main` remains available as an explicit form.

Use `-p` to customize the port mapping. Supplying any custom `-p` replaces the complete default port set, so include both TCP and UDP mappings for P2P. For more parameters, see [Options](#options).

```shell
$ bash docker.sh --run --net main \
    -p 8080:8090 \
    -p 40051:50051 \
    -p 18888:18888 \
    -p 18888:18888/udp
```

#### Full node on the private network

You can also run a private network with the configuration maintained by `tron-deployment`. If `config/private_net_config.conf` does not exist in the current directory, the script downloads it automatically. An existing local configuration is reused so that local changes are preserved.

```shell
$ bash docker.sh --run --net private
```

To replace an existing local copy with the latest maintained configuration, explicitly request an update. This overwrites `config/private_net_config.conf`.

```shell
$ bash docker.sh --run --net private --update-config true
```

#### Configuration

Mainnet uses the configuration bundled in the image and never downloads another configuration. The `private` network option uses `config/private_net_config.conf` from the current directory, downloading it from `tron-deployment` only when it is missing or an update is explicitly requested.

Nile is intentionally not supported by this script because it may require features that are not yet available on the mainnet source revision. Follow the Nile-specific build instructions in the project README instead.

Alternatively, mount a configuration into the container and select it with `-c`:

```shell
$ bash docker.sh --run \
    -v /absolute/path/custom.conf:/java-tron/custom.conf:ro \
    -c /java-tron/custom.conf
```

### View logs

Use `--log` to follow the java-tron service log:

```shell
$ bash docker.sh --log | grep 'PushBlock'
```

### Stop the service

Use `--stop` to stop the java-tron container:

```shell
$ bash docker.sh --stop
```

## Build Image

To build an image with a custom name, change these variables in `docker.sh`:

- `DOCKER_REPOSITORY`: repository name
- `DOCKER_IMAGES`: image name
- `DOCKER_TARGET`: image tag

```shell
DOCKER_REPOSITORY="your_repository"
DOCKER_IMAGES="java-tron"
DOCKER_TARGET="1.0"
```

Then build the image:

```shell
$ bash docker.sh --build
```

The script detects the Docker daemon architecture by default. You can also select the target architecture explicitly:

```shell
$ bash docker.sh --build amd64
$ bash docker.sh --build arm64
```

When the script is used from a java-tron checkout, the Dockerfile and build context are resolved relative to `docker.sh`, regardless of the current working directory. If only `docker.sh` was downloaded, the required architecture-specific Dockerfile is downloaded into a temporary build context and removed after the build.

## Options

Parameters for all functions:

- **`--build [amd64|arm64]`**: build a local image, optionally for the specified architecture
- **`--pull`**: download an image from Docker Hub
- **`--run`**: run the image
- **`--start`**: start the existing java-tron container
- **`--log`**: follow the java-tron log in the container
- **`--stop`**: stop the running container
- **`--rm`**: remove the container without removing the image
- **`-p`**: publish a container port using `-p hostPort:containerPort[/protocol]`; custom mappings replace all defaults
- **`-c`**: specify another java-tron configuration file in the container
- **`-v`**: bind mount a volume using `-v host-src:container-dest`; `host-src` must be an absolute path
- **`--net`**: select `main` or `private`; a missing private configuration is downloaded automatically
- **`--update-config`**: set to `true` with `--net private` to replace the local private configuration
