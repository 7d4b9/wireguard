# WireGuard

Build and deployment infrastructure for WireGuard userspace implementations and tools.

This repository provides reproducible builds, platform-specific configurations, and deployment scripts for integrating devices into the Vegito private WireGuard network.

The initial supported target is **Synology NAS running Linux on ARMv7**.

## Overview

The repository integrates two upstream WireGuard components:

- **wireguard-go** — Userspace WireGuard implementation written in Go.
- **wireguard-tools** — WireGuard configuration and management utilities, including `wg`.

The build system uses Docker to produce architecture-specific binaries without requiring development tools to be installed directly on the target devices.

Platform-specific build definitions and deployment procedures are maintained in dedicated directories.

## Repository structure

```text
wireguard/
├── LICENSE
├── Makefile
├── README.md
│
├── synology/
│   ├── README.md
│   ├── synology.mk
│   ├── start.sh
│   └── dist/
│       └── linux-armv7/
│           ├── wg
│           └── wireguard-go
│
├── wireguard-go/
└── wireguard-tools/
```

### Components

| Directory | Description |
|---|---|
| `wireguard-go/` | Upstream WireGuard userspace implementation |
| `wireguard-tools/` | Upstream WireGuard management utilities |
| `synology/` | Synology ARMv7 build and deployment support |
| `synology/dist/` | Generated platform-specific binaries |

## Build system

The root `Makefile` provides a common entry point for platform-specific builds.

Platform implementations are included through dedicated Makefiles.

Currently supported:

| Platform | Architecture | Implementation |
|---|---|---|
| Synology DSM | Linux ARMv7 | `synology/synology.mk` |

### Requirements

- Docker Engine
- Docker CLI
- GNU Make
- Git
- Docker support for the required build platforms

The Synology build uses:

- Alpine Linux ARMv7 for statically linked `wg`.
- Go running in an AMD64 container for cross-compiling `wireguard-go`.

### Build all supported targets

```bash
make build
```

### Build Synology binaries

```bash
make build-synology
```

### Build individual components

Build `wg`:

```bash
make build-wg-synology
```

Build `wireguard-go`:

```bash
make build-wireguard-go-synology
```

### Clean generated binaries

```bash
make clean
```

Or:

```bash
make clean-synology
```

## Build artifacts

Synology ARMv7 binaries are generated in:

```text
synology/dist/linux-armv7/
├── wg
└── wireguard-go
```

The binaries are intended to run on compatible ARMv7 Linux systems.

The `wg` executable is statically linked against musl libc.

The `wireguard-go` executable is compiled with:

```text
GOOS=linux
GOARCH=arm
GOARM=7
CGO_ENABLED=0
```

Verify the resulting binaries:

```bash
file synology/dist/linux-armv7/*
```

## Deployment

Deployment is platform-specific.

The Synology implementation provides a startup script for running WireGuard in userspace on devices without a compatible WireGuard kernel module.

The deployment process includes:

1. Building the ARMv7 binaries.
2. Installing the binaries on the target NAS.
3. Generating device-specific WireGuard keys.
4. Configuring the WireGuard peer.
5. Configuring the network interface and routes.
6. Starting WireGuard.
7. Optionally configuring automatic startup through Synology DSM.

For installation instructions, network configuration, routing and troubleshooting, see:

**[Synology ARMv7 documentation](synology/README.md)**

## Network integration

The initial deployment targets the Vegito private WireGuard backbone.

The implementation is designed to preserve existing network configurations.

In particular:

- WireGuard runs independently of the NAS default network gateway.
- Only explicitly configured destination networks are routed through the tunnel.
- Existing NAS services continue using their original network interfaces.
- Each device maintains its own WireGuard identity and configuration.

The network topology and device-specific settings are documented in the Synology README.

## Upstream projects

### wireguard-go

Userspace implementation of the WireGuard protocol.

Official repository: https://github.com/WireGuard/wireguard-go

### wireguard-tools

Configuration and management tools for WireGuard.

Official repository: https://git.zx2c4.com/wireguard-tools/

### WireGuard

Official documentation: https://www.wireguard.com/

## Security

Private keys, peer configurations containing secrets, and deployment-specific credentials must not be committed to the repository.

Generated binaries should be verified before deployment.

WireGuard interfaces and routes should be configured with the minimum network access required by each target system.

## License

See [LICENSE](LICENSE) for the license applicable to this repository.

The upstream WireGuard components retain their respective licenses:

- `wireguard-go/LICENSE`
- `wireguard-tools/COPYING`
