# Docker Shell Guide

java-tron support containerized processes, we maintain a Docker image with latest version build from our master branch on DockerHub. To simplify the use of Docker and common docker commands, we also provide a shell script to help you better manage container services，this guide describes how to use the script tool.


## Prerequisites

Requires a docker to be installed on the system. Docker version >=20.10.12. 


## Quick Start

Shell can be obtained from the java-tron project or independently, you can get the script from [here](https://github.com/tronprotocol/java-tron/blob/develop/docker/docker.sh) or download via the wget:
```shell
$ wget https://raw.githubusercontent.com/tronprotocol/java-tron/develop/docker/docker.sh
```

### Pull the mirror image
Get the `tronprotocol/java-tron` image from the DockerHub, this image contains the full JDK environment and the host network configuration file, using the script for simple docker operations.
```shell
$ bash docker.sh --pull
```

### Run the service
Before running the java-tron service, make sure some ports on your local machine are open,the image has the following ports automatically exposed:
- `8090`: used by the HTTP based JSON API
- `50051`: used by the GRPC based API
- `18888`: TCP and UDP, used by the P2P protocol running the network

#### Full node on the main network

```shell
$ bash docker.sh --run
```
The mainnet configuration is bundled in the image at `/java-tron/config.conf` and comes from the
same java-tron revision used to build the image. `--net main` remains available as an explicit form.

You can use `-p` to customize the port mapping. For more custom parameters, see
[Options](#Options).

```shell
$ bash docker.sh --run --net main -p 8080:8090 -p 40051:50051
```

#### Full node on the private network
You can also run a private network with the configuration maintained by `tron-deployment`.
If `config/private_net_config.conf` does not exist in the current directory, the script downloads
it automatically. An existing local configuration is reused so that local changes are preserved.
```shell
$ bash docker.sh --run --net private
```

To replace an existing local copy with the latest maintained configuration, explicitly request an
update. This overwrites `config/private_net_config.conf`.

```shell
$ bash docker.sh --run --net private --update-config true
```

#### Configuration
Mainnet uses the configuration bundled in the image and never downloads another configuration.
The `private` network option uses `config/private_net_config.conf` from the current directory,
downloading it from `tron-deployment` only when it is missing or an update is explicitly requested.

Nile is intentionally not supported by this script because it may require features that are not
yet available on the mainnet source revision. Follow the Nile-specific build instructions in the
project README instead.

Alternatively, mount a configuration into the container and select it with `-c`:

```shell
$ bash docker.sh --run \
    -v /absolute/path/custom.conf:/java-tron/custom.conf:ro \
    -c /java-tron/custom.conf
```


### View logs
If you want to see the logs of the java-tron service, please use the `--log` parameter

```shell
$ bash docker.sh --log | grep 'PushBlock'
```
### Stop the service

If you want to stop the container of java-tron, you can execute

```shell
$ bash docker.sh --stop
```

## Build Image

If you do not want to use the default official image, you can also compile your own local image, first you need to change some parameters in the shell script to specify your own mirror info.
`DOCKER_REPOSITORY` is your repository name
`DOCKER_IMAGES` is the image name
`DOCKER_TARGET` is the version number, here is an example:

```shell
DOCKER_REPOSITORY="your_repository"
DOCKER_IMAGES="java-tron"
DOCKER_TARGET="1.0"
```

then execute the build:

```shell
$ bash docker.sh --build
```

The script detects the Docker daemon architecture by default. You can also select the target
architecture explicitly:

```shell
$ bash docker.sh --build amd64
$ bash docker.sh --build arm64
```

When the script is used from a java-tron checkout, the Dockerfile and build context are resolved
relative to `docker.sh`, regardless of the current working directory. If only `docker.sh` was
downloaded, the required architecture-specific Dockerfile and entrypoint are downloaded into a
temporary build context and removed after the build.

## Options

Parameters for all functions：

* **`--build [amd64|arm64]`** building a local mirror image, optionally for the specified architecture
* **`--pull`** download a docker mirror from **DockerHub**
* **`--run`** run the docker mirror
* **`--log`** exporting the java-tron run log on the container
* **`--stop`** stopping a running container
* **`--rm`** remove container,only deletes the container, not the image
* **`-p`** publish a container's port to the host, format:`-p hostPort:containerPort`
* **`-c`** specify other java-tron configuration file in the container
* **`-v`** bind mount a volume for the container,format: `-v host-src:container-dest`, the `host-src` is an absolute path
* **`--net`** select `main` or `private`; a missing private configuration is downloaded automatically
* **`--update-config`** set to `true` with `--net private` to replace the local private configuration
