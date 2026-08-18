# Docker Shell Guide

This guide covers the `docker.sh` workflow maintained in the java-tron repository. The Bash helper can build an image locally, pull the `tronprotocol/java-tron` image from Docker Hub, and operate a single FullNode container.

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
wget https://raw.githubusercontent.com/tronprotocol/java-tron/master/docker/docker.sh
```

The standalone download follows the stable `master` workflow. To test changes from `develop` or an uncommitted working tree, use `docker/docker.sh` from the corresponding java-tron checkout instead. All examples below assume that `docker.sh` is in the current directory.

### Pull the image

The image contains the java-tron distribution and a Java runtime. It also bakes in `/java-tron/config.conf` from the `tron-deployment` `master` branch at build time. `docker.sh --run` does not use that file; it passes `-c` and a host-mounted configuration instead. A plain `docker run` without `-c` reads the baked-in file, which is not pinned to the image's java-tron version.

```shell
bash docker.sh --pull
```

### Run a FullNode

`docker.sh` publishes the following ports by default:

- `127.0.0.1:8090:8090/tcp`: HTTP JSON API, accessible only from the Docker host
- `127.0.0.1:50051:50051/tcp`: gRPC API, accessible only from the Docker host
- `18888:18888/tcp` and `18888:18888/udp`: P2P communication, accessible through the host network interfaces

HTTP and gRPC are bound to loopback by default to prevent accidental network or public exposure. P2P remains externally reachable so that the node can communicate with peers.

> **Storage and synchronization:** The default Mainnet configuration starts a full FullNode. It does not enable Lite FullNode mode or preload a data snapshot. When `output-directory` under the selected data directory is empty, the node synchronizes the complete Mainnet database from genesis; allocate approximately 3.5–4 TB of high-performance SSD storage for this mode. The script persists this database on the host, but the host filesystem must still have sufficient capacity. To reduce initial synchronization time or use the Lite FullNode storage tier, import and configure a compatible [FullNode or Lite FullNode data snapshot](https://tronprotocol.github.io/documentation-en/using_javatron/installing_javatron/#data-snapshot) for the selected network and java-tron version before starting the node.

Run a Mainnet FullNode:

```shell
bash docker.sh --run --net main
```

The helper manages one container named `tronprotocol-java-tron`. Running `--run` again while that container exists returns an error; use `--start` to reuse a stopped container, or `--rm` before creating a replacement. If no local image exists, `--run` prompts before pulling when stdin is a terminal. In non-interactive environments it exits with an error; run `--pull` or `--build` first.

Use repeatable `-p` options to change individual mappings. Defaults are retained for container ports and protocols that are not explicitly mapped, so the following command changes only the HTTP and gRPC host ports:

```shell
bash docker.sh --run --net main \
    -p 127.0.0.1:8080:8090 \
    -p 127.0.0.1:40051:50051
```

To provide a network-accessible API, explicitly replace the relevant loopback mapping. For example, the following publishes HTTP on all IPv4 interfaces:

```shell
bash docker.sh --run --net main -p 0.0.0.0:8090:8090
```

Only expose HTTP or gRPC after restricting access with a firewall, trusted reverse proxy, or equivalent network controls.

Run a Nile Testnet FullNode:

```shell
bash docker.sh --run --net test
```

Run a private-network FullNode:

```shell
bash docker.sh --run --net private
```

## Configuration

For `main`, `test`, and `private`, the script downloads the corresponding configuration file from the [tron-deployment repository](https://github.com/tronprotocol/tron-deployment). By default, an existing local configuration is retained; a missing or empty file is downloaded automatically for the initial run.

Configuration templates are maintained separately from java-tron. Verify that a downloaded configuration is compatible with the image version before using it in production.

Use `--update-config true` to explicitly refresh the selected local copy before creating the container:

```shell
bash docker.sh --run --net main --update-config true
```

Use `-c` to select a custom configuration file. The value must be a path inside the container, so mount the host file with `-v`:

```shell
bash docker.sh --run --net main \
    -v /absolute/path/custom.conf:/java-tron/custom.conf:ro \
    -c /java-tron/custom.conf
```

## FullNode arguments

Use `--` to end `docker.sh` option parsing and pass all remaining arguments unchanged to FullNode. For example, to explicitly keep P2P enabled:

```shell
bash docker.sh --run --net main -- --p2p-disable false
```

Options before `--` configure the Docker helper; options after it are passed to `./bin/FullNode`. Use the helper's `-c` option for the configuration path instead of passing a second `-c` after `--`.

Witness options such as `-w` and `--witness-address` can also be passed after `--`. Do not pass `--private-key` or `--password`: command arguments may be visible in process listings and are retained in Docker container metadata. This helper does not by itself provide the secret delivery, key protection, monitoring, backup, and upgrade procedures required for a production Super Representative deployment. Follow the [Starting a Block Production Node](https://tronprotocol.github.io/documentation-en/using_javatron/installing_javatron/#starting-a-block-production-node) guide, use an encrypted keystore, and provide its password through the production deployment's secret-management mechanism.

By default, the script mounts persistent directories relative to the shell's current working directory when `docker.sh` is invoked, not relative to the script file:

```text
./config           -> /java-tron/config (read-only)
./output-directory -> /java-tron/output-directory
./logs             -> /java-tron/logs
```

The default configuration mount is read-only because FullNode only needs to read it. This prevents the container from persisting configuration changes onto the host. Additional `-v` options retain these defaults. A custom mount replaces a default only when it uses the same container destination; callers that explicitly replace the configuration mount control its access mode.

Use `--data-dir` to keep these three directories in an explicit location, preferably outside the source checkout. Relative values are resolved against the invocation directory:

```shell
bash docker.sh --run --net main --data-dir /var/lib/java-tron
```

This produces `/var/lib/java-tron/config` (still mounted read-only at `/java-tron/config`), `/var/lib/java-tron/output-directory`, and `/var/lib/java-tron/logs` host mounts. The default data directory is the current working directory, so running `--run` from a checkout writes `config/`, `output-directory/`, and `logs/` into that tree. Use `--data-dir` to keep those runtime files out of the Git worktree. Persisting `logs` also keeps `tron.log` available after the container is removed.

## Memory and JVM options

These memory defaults come from `docker.sh`, not from the image or the packaged `java-tron.vmoptions` file. A plain `docker run` or `bin/FullNode` invocation without the helper still uses the JVM ergonomics default of about 25% of visible memory.

`docker.sh` applies a minimum helper profile: a `16g` container memory limit, a 2 GB initial heap, and a maximum heap of up to 60% of that container limit:

```text
-Xms2g -XX:MaxRAMPercentage=60.0
```

JDK 8 images also receive `-XX:MaxDirectMemorySize=1g`. JDK 17 images already include that option in `java-tron.vmoptions`, so the helper does not add it again. The script inspects the image architecture to decide this, not the host `uname`.

This is a minimum **memory** profile for lower-load deployments; it does not enable Lite FullNode mode or reduce the database storage requirement described above. For stable Mainnet operation, use at least `32g`; Super Representative nodes require at least `64g`. See the [Mainnet hardware requirements](../README.md#hardware-requirements-for-mainnet) for the complete deployment tiers.

Use `--memory` to change the container memory limit. When the default helper JVM options are retained, the maximum heap scales with this limit:

```shell
bash docker.sh --run --net main --memory 32g
```

To replace the helper JVM options entirely, use `--jvm-opts`. The replacement is not merged with the defaults, so include every option you need:

```shell
bash docker.sh --run --net main --memory 32g \
    --jvm-opts "-Xms4g -Xmx18g -XX:MaxDirectMemorySize=2g"
```

The packaged `java-tron.vmoptions` file remains active. It contains architecture- and JDK-specific garbage collector settings, so do not use `--jvm-opts` to copy or switch GC options between JDK 8 and JDK 17 deployments.

Environment variables for custom wrapper scripts or derived images can be passed with repeatable `-e` or `--env` options. `MY_VARIABLE` is only a placeholder. JVM option environment variables (`JAVA_OPTS`, `FULL_NODE_OPTS`, `JAVA_TOOL_OPTIONS`, `_JAVA_OPTIONS`, and `JDK_JAVA_OPTIONS`) are rejected because they can replace or bypass the helper profile. Use `--jvm-opts` instead.

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

`--build` selects `Dockerfile` on x86_64/amd64 and `arm64/Dockerfile` on arm64/aarch64. For a remote or standalone `--build`, a missing Dockerfile is downloaded from the java-tron `master` branch. `--source local` uses the Dockerfile from the same checkout and fails if that file is not present.

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

In local mode, `docker.sh` runs the Gradle `:framework:distZip` task on the host, uses the architecture-specific Dockerfile from the same checkout, extracts the resulting distribution into a temporary directory, and adds the Mainnet configuration file. The build fails instead of downloading a Dockerfile when the checkout does not contain the expected file. Only the staged distribution and local Dockerfile are sent to the Docker daemon; the rest of the source checkout, node database, environment files, and local keys are not part of the Docker build context.

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
| `-h`, `--help` | Show command usage without requiring a Docker daemon. |
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
| `-p [HOST_IP:]HOST_PORT:CONTAINER_PORT[/PROTOCOL]` | Publish a container port. Repeat to customize multiple mappings. |
| `-c CONTAINER_PATH` | Use a configuration file at the specified path inside the container. |
| `-v HOST_PATH:CONTAINER_PATH[:OPTIONS]` | Add or replace a bind mount. The host path should be absolute. A replacement for `/java-tron/config` uses the caller's access mode instead of the default read-only mount. |
| `-e NAME=VALUE`, `--env NAME=VALUE` | Set a container environment variable. This option can be repeated. JVM option environment variables are rejected; use `--jvm-opts`. |
| `--net main\|test\|private` | Select the Mainnet, Nile Testnet, or private-network configuration. |
| `--update-config true\|false` | Refresh the selected configuration before creating the container. Default: `false`; missing or empty files are still downloaded. |
| `--data-dir PATH` | Store the default `config`, `output-directory`, and `logs` mounts under this host path. Default: invocation directory. The default `config` mount remains read-only in the container. |
| `--memory LIMIT` | Set the container memory limit. Default: `16g`. |
| `--jvm-opts "OPTIONS"` | Replace the JVM options supplied by `docker.sh`. The image itself does not set these defaults. |
| `-- FULLNODE_ARGS...` | Pass all remaining arguments unchanged to FullNode. |
