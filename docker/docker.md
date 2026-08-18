# Docker Shell Guide

This guide covers the `docker.sh` workflow maintained in the java-tron repository. It provides the `tronprotocol/java-tron` image on Docker Hub and a Bash helper for building or pulling an image and operating a single FullNode container. The `latest` image is built from the java-tron `master` branch.

For Docker Compose deployments, multi-node private networks, and dedicated image build and test tooling, use the [tron-docker repository](https://github.com/tronprotocol/tron-docker). The two workflows are maintained independently; their commands, configuration, and defaults are not interchangeable.

## Prerequisites

- Docker Engine 23.0 or later, with BuildKit and the Buildx plugin available
- Bash
- `curl` or `wget` when configuration files or Dockerfiles need to be downloaded
- For `--source local` only: `unzip` and the architecture-specific JDK used by java-tron (JDK 8 on x86_64/amd64 or JDK 17 on arm64/aarch64)

Do not invoke the script with `sh`. The script uses Bash-specific syntax.

## Quick start

Use `docker/docker.sh` from a java-tron checkout, or download it separately:

```shell
wget https://raw.githubusercontent.com/tronprotocol/java-tron/develop/docker/docker.sh
```

All examples below assume that `docker.sh` is in the current directory.

### Pull the image

The image contains the java-tron distribution, a Java runtime, and a Mainnet configuration file:

```shell
bash docker.sh --pull
```

### Run a FullNode

`docker.sh` publishes the following ports by default:

- `8090/tcp`: HTTP JSON API
- `50051/tcp`: gRPC API
- `18888/tcp` and `18888/udp`: P2P communication

Run a Mainnet FullNode:

```shell
bash docker.sh --run --net main
```

Use repeatable `-p` options to change individual mappings. Defaults are retained for container ports and protocols that are not explicitly mapped, so the following command changes only the HTTP and gRPC host ports:

```shell
bash docker.sh --run --net main \
    -p 8080:8090 \
    -p 40051:50051
```

Run a Nile Testnet FullNode:

```shell
bash docker.sh --run --net test
```

Run a private-network FullNode:

```shell
bash docker.sh --run --net private
```

## Configuration

For `main`, `test`, and `private`, the script downloads the corresponding configuration file from the [tron-deployment repository](https://github.com/tronprotocol/tron-deployment). By default, the file is refreshed each time a container is created.

Configuration templates are maintained separately from java-tron. Verify that a downloaded configuration is compatible with the image version before using it in production.

After the initial download, use `--update-config false` to retain the local copy. If the selected file does not exist, the script still downloads it for the initial run.

```shell
bash docker.sh --run --net main --update-config false
```

Use `-c` to select a custom configuration file. The value must be a path inside the container, so mount the host file with `-v`:

```shell
bash docker.sh --run --net main \
    -v /absolute/path/custom.conf:/java-tron/custom.conf:ro \
    -c /java-tron/custom.conf
```

By default, the script also mounts these persistent directories from the current host directory:

```text
./config           -> /java-tron/config
./output-directory -> /java-tron/output-directory
```

Additional `-v` options retain these defaults. A custom mount replaces a default only when it uses the same container destination.

## Memory and JVM options

By default, `docker.sh` uses the minimum memory profile for a FullNode: a `16g` container memory limit, a 2 GB initial heap, a maximum heap of up to 60% of the container memory, and a 1 GB direct-memory limit:

```text
-Xms2g -XX:MaxRAMPercentage=60.0 -XX:MaxDirectMemorySize=1g
```

This profile is intended for minimum-resource or lower-load deployments. For stable Mainnet operation, use at least `32g`; Super Representative nodes require at least `64g`. See the [Mainnet hardware requirements](../README.md#hardware-requirements-for-mainnet) for the complete deployment tiers.

Use `--memory` to change the container memory limit. When the default JVM options are retained, the maximum heap scales with this limit:

```shell
bash docker.sh --run --net main --memory 32g
```

For a stable Mainnet profile with explicit heap and direct-memory limits, use `--jvm-opts` to replace the memory-related JVM options supplied by `docker.sh`:

```shell
bash docker.sh --run --net main --memory 32g \
    --jvm-opts "-Xms4g -Xmx18g -XX:MaxDirectMemorySize=2g"
```

The packaged `java-tron.vmoptions` file remains active. It contains architecture- and JDK-specific garbage collector settings, so do not use `--jvm-opts` to copy or switch GC options between JDK 8 and JDK 17 deployments.

Environment variables for custom wrapper scripts or derived images can be passed with repeatable `-e` or `--env` options. `MY_VARIABLE` is only a placeholder:

```shell
bash docker.sh --run --net main -e "MY_VARIABLE=value"
```

## Container lifecycle

View the java-tron log:

```shell
bash docker.sh --log
```

For example, filter block-processing messages with:

```shell
bash docker.sh --log | grep 'PushBlock'
```

Stop and restart the container:

```shell
bash docker.sh --stop
bash docker.sh --start
```

Remove the container without deleting the image or persisted host data:

```shell
bash docker.sh --rm
```

The lifecycle commands return a non-zero status when the target container does not exist, the container cannot be queried, or the underlying Docker operation fails. This allows service managers and automation scripts to detect failures reliably.

## Build an image

`--build` selects `Dockerfile` on x86_64/amd64 and `arm64/Dockerfile` on arm64/aarch64. When the selected Dockerfile is not present, the script downloads it from the java-tron `develop` branch.

For backward compatibility, `--build` without source options clones and compiles the remote java-tron `master` branch. Local working-tree changes are not included:

```shell
bash docker.sh --build
```

Use `--source-ref` to build another remote branch or tag. `--source-repository` can select another public Git repository:

```shell
bash docker.sh --build \
    --source remote \
    --source-ref develop
```

From a java-tron checkout, use `--source local` to compile the current working tree, including uncommitted changes:

```shell
bash docker/docker.sh --build --source local
```

In local mode, `docker.sh` runs the Gradle `:framework:distZip` task on the host, extracts the resulting distribution into a temporary directory, and adds the Mainnet configuration file. Only that staged distribution and the selected Dockerfile are sent to the Docker daemon; the source checkout, node database, environment files, and local keys are not part of the Docker build context.

The two architecture-specific Dockerfiles each provide `local` and `remote` BuildKit targets. `docker.sh` selects the appropriate target and supplies its required minimal context. A plain Dockerfile build defaults to the historical `remote` target, but direct `local` target builds require callers to stage the distribution as `java-tron/` first.

To change the local image name, edit these variables in `docker.sh`:

```shell
DOCKER_REPOSITORY="your_repository"
DOCKER_IMAGES="java-tron"
DOCKER_TARGET="1.0"
```

## Options

| Option | Description |
| --- | --- |
| `--build` | Build an image for the host architecture. Defaults to remote `master` source for backward compatibility. |
| `--source local\|remote` | Select a host-built distribution or a remote source build for `--build`. Default: `remote`. |
| `--source-ref REF` | Select the remote branch or tag for `--build`. Default: `master`. |
| `--source-repository URL` | Select the public remote Git repository for `--build`. |
| `--pull` | Pull the configured image from Docker Hub. |
| `--run` | Create and start a container. |
| `--start` | Start the existing stopped container. |
| `--log` | Follow the java-tron log in the container. |
| `--stop` | Stop the running container. |
| `--rm` | Remove the container without removing the image or host data. |
| `-p HOST:CONTAINER[/PROTOCOL]` | Publish a container port. Repeat to customize multiple mappings. |
| `-c CONTAINER_PATH` | Use a configuration file at the specified path inside the container. |
| `-v HOST_PATH:CONTAINER_PATH[:OPTIONS]` | Add or replace a bind mount. The host path should be absolute. |
| `-e NAME=VALUE`, `--env NAME=VALUE` | Set a container environment variable. This option can be repeated. |
| `--net main\|test\|private` | Select the Mainnet, Nile Testnet, or private-network configuration. |
| `--update-config true\|false` | Refresh the selected configuration before creating the container. Default: `true`. |
| `--memory LIMIT` | Set the container memory limit. Default: `16g`. |
| `--jvm-opts "OPTIONS"` | Replace the memory-related JVM options supplied by `docker.sh`. |
