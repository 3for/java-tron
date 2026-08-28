# How to quick start

## Introduction

This guide covers three common ways to get started with TRON:

- Run a mainnet FullNode with the official java-tron Docker helper.
- Start an isolated local development chain with
  [TRON Runtime Environment (TRE)](https://hub.docker.com/r/tronbox/tre).
- Deploy a multi-node private network with the official
  [tron-docker](https://github.com/tronprotocol/tron-docker/tree/main/private_net) configuration.

## Dependencies

Install the latest Docker release for your platform:

- [macOS](https://docs.docker.com/desktop/setup/install/mac-install/)
- [Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
- [Linux](https://docs.docker.com/engine/install/)

## Run a mainnet FullNode

The official `docker.sh` helper manages image builds, pulls, container startup, ports,
configuration, logs, and lifecycle operations.

### Build the Docker image from source

Clone the java-tron repository and enter its directory:

```shell
git clone https://github.com/tronprotocol/java-tron.git
cd java-tron
```

From the repository root, build the image. The helper detects the Docker daemon architecture and
selects the matching Dockerfile:

```shell
bash docker/docker.sh --build
```

### Use the official Docker image

Alternatively, pull the official image from Docker Hub:

```shell
bash docker/docker.sh --pull
```

### Start and manage the FullNode

Start a mainnet FullNode with the bundled configuration and default HTTP, gRPC, and P2P port
mappings:

```shell
bash docker/docker.sh --run
```

View its logs:

```shell
bash docker/docker.sh --log
```

Stop the container:

```shell
bash docker/docker.sh --stop
```

For private networks, custom configuration files, custom port mappings, architecture selection,
and other lifecycle commands, see the [Docker Shell Guide](docker/docker.md).

## Start a local development chain with TRE

[TRE](https://hub.docker.com/r/tronbox/tre) is the maintained successor for local smart-contract
and DApp development. It provides a single-container development chain with funded test accounts,
automatic block production, and commonly used HTTP and event APIs on port `9090`.

Pull and run the current stable image:

```shell
docker pull tronbox/tre
docker run --rm \
  --name tron \
  -p 127.0.0.1:9090:9090 \
  -e useDefaultPrivateKey=true \
  tronbox/tre
```

Check that the environment is ready:

```shell
curl -fsS http://127.0.0.1:9090/healthcheck
```

The default image tag follows the current stable release. Pin a versioned tag or image digest in
CI when reproducible builds are required. See the
[TronBox documentation](https://tronbox.io/docs/quickstart) for contract development and deployment
workflows.

> **Warning:** TRE is intended only for isolated development and testing. The default private key,
> funded accounts, and administrative APIs are not secure. Keep port `9090` bound to localhost and
> never expose this environment to production or an untrusted network.

## Deploy a multi-node private network

Use the official `tron-docker/private_net` setup when testing P2P communication, consensus, node
operations, or workflows that require more than one java-tron process:

```shell
git clone https://github.com/tronprotocol/tron-docker.git
cd tron-docker/private_net
docker compose up -d
```

This setup starts a block-producing SR node and a regular FullNode. Its bundled genesis accounts,
keys, and configuration are suitable for local testing only. Review and replace them before using
the setup in a shared or security-sensitive environment. See the
[private network documentation](https://github.com/tronprotocol/tron-docker/tree/main/private_net)
for configuration and additional nodes.
