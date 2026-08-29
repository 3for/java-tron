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

Before running java-tron, make sure the required ports are available on the host. By default, HTTP and gRPC APIs are bound to the host loopback interface, while the P2P port is available on all host interfaces. Mainnet uses:

- `127.0.0.1:8090`: used by the HTTP-based JSON API
- `127.0.0.1:50051`: used by the gRPC-based API
- `18888`: TCP and UDP on all host interfaces, used by the P2P protocol

#### Full node on the main network

```shell
$ bash docker.sh --run
```

The mainnet configuration is bundled in the image at `/java-tron/config.conf` and comes from the same java-tron revision used to build the image. `--net main` remains available as an explicit form.

Use `-p` to customize the port mapping. Supplying any custom `-p` replaces the complete default port set, so include both TCP and UDP mappings for P2P. For more parameters, see [Options](#options).

```shell
$ bash docker.sh --run --net main \
    -p 127.0.0.1:8080:8090 \
    -p 127.0.0.1:40051:50051 \
    -p 18888:18888 \
    -p 18888:18888/udp
```

#### Single-node private network

You can also run a single-node private network with the configuration maintained by `tron-deployment`. If `config/private_net_config.conf` does not exist in the current directory, the script downloads it automatically. An existing local configuration is reused so that local changes are preserved.

```shell
$ bash docker.sh --run --net private
```

Private mode starts FullNode with `--witness` so that the genesis witness produces blocks. Its default ports match `private_net_config.conf`:

- `127.0.0.1:16667`: used by the HTTP-based JSON API
- `127.0.0.1:50051`: used by the gRPC-based API
- `16666`: TCP and UDP on all host interfaces, used by the private P2P network

The downloaded configuration contains a publicly known development witness key and genesis accounts. Use it only for isolated local development. For a multi-node, shared, or security-sensitive private network, use the maintained [`tron-docker/private_net`](https://github.com/tronprotocol/tron-docker/tree/main/private_net) setup and replace its keys and configuration as appropriate.

To replace an existing local copy with the latest maintained configuration, explicitly request an update. This overwrites `config/private_net_config.conf`.

```shell
$ bash docker.sh --run --net private --update-config true
```

#### Configuration

Mainnet uses the configuration bundled in the image and never downloads another configuration. The `private` network option uses `config/private_net_config.conf` from the current directory, downloading it from `tron-deployment` only when it is missing or an update is explicitly requested. It also enables witness mode so that the single-node network can produce blocks.

Nile is intentionally not supported by this script because it may require features that are not yet available on the mainnet source revision. Follow the Nile-specific build instructions in the project README instead.

Alternatively, mount a configuration into the container and select it with `-c`:

```shell
$ bash docker.sh --run \
    -v /absolute/path/custom.conf:/java-tron/custom.conf:ro \
    -c /java-tron/custom.conf
```

### Data and log persistence

By default, the helper bind-mounts `output-directory` from the directory where `docker.sh` is executed to `/java-tron/output-directory` in the container. The blockchain database therefore remains on the host after the container is removed. Make sure that the current filesystem has sufficient space, or mount a dedicated data directory:

```shell
$ mkdir -p "$PWD/mainnet-data"
$ bash docker.sh --run --net main \
    -v "$PWD/mainnet-data:/java-tron/output-directory"
```

Do not reuse one database directory across different networks. Use separate directories for mainnet and private-network data.

Application logs are not persisted by default; they remain in the container writable layer and are deleted with the container. To retain logs after `--rm`, mount a host directory explicitly:

```shell
$ mkdir -p "$PWD/logs"
$ bash docker.sh --run --net main \
    -v "$PWD/logs:/java-tron/logs"
```

Adding a log or configuration volume does not disable the default database mount. The default is replaced only when a custom volume targets `/java-tron/output-directory`.

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
