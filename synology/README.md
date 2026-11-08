# WireGuard

Build and deployment of WireGuard userspace binaries for ARMv7 Synology NAS devices.

This repository provides a reproducible build environment and startup scripts for connecting Synology NAS devices to the existing Vegito WireGuard backbone without changing their default gateways or disrupting DSM, NFS, and SFTPGo.

The implementation uses:

- **wireguard-go** — Userspace WireGuard implementation written in Go.
- **wireguard-tools** — WireGuard configuration utilities, including `wg`.
- **Docker** — Isolated ARMv7 and cross-compilation build environments.
- **Synology DSM** — Deployment and boot-time execution.

## 1. Architecture

### Network topology

```text
                         WireGuard backbone
                            10.6.6.0/24
                                  |
                         GL.iNet Beryl AX
                            10.6.6.1
                                  |
             +--------------------+-------------------+
             |                    |                   |
         PC Debian             MacBook           NFS Bridge
         10.6.6.2              10.6.6.3          10.6.6.4
                                  |
                         +--------+--------+
                         |                 |
                     NAS Vanves         NAS PDC
                     10.6.6.5           10.6.6.6
                     ARMv7              ARMv7
```

The NAS devices connect as independent peers to the existing Beryl WireGuard server.

| Device | WireGuard IP | Role |
|---|---|---|
| Beryl AX | `10.6.6.1` | WireGuard server |
| PC Debian | `10.6.6.2` | Lab infrastructure |
| MacBook | `10.6.6.3` | Development workstation |
| NFS Bridge | `10.6.6.4` | Network bridge |
| NAS Vanves | `10.6.6.5` | Synology client (planned) |
| NAS PDC | `10.6.6.6` | Synology client (planned) |

The proposed NAS addresses must be confirmed available and registered on the server before use.

### Design principles

- Do not expose Vault Raft ports publicly.
- Keep each NAS's original default route.
- Leave DSM, NFS, and SFTPGo traffic on existing network interfaces.
- Route only the WireGuard backbone through the tunnel.
- Give each NAS its own WireGuard key pair.
- Keep private keys and host-specific configuration outside Git.
- Start WireGuard independently of Vault.

## 2. Repository structure

```text
wireguard/
├── Makefile
├── README.md
├── synology/
│   ├── synology.mk
│   ├── start.sh
│   └── dist/
│       └── linux-armv7/
│           ├── wg
│           └── wireguard-go
├── wireguard-go/
└── wireguard-tools/
```

| Path | Description |
|---|---|
| `Makefile` | Main build entry point |
| `synology/synology.mk` | Synology-specific build targets |
| `synology/start.sh` | WireGuard startup script |
| `synology/dist/linux-armv7/wg` | Compiled ARMv7 configuration utility |
| `synology/dist/linux-armv7/wireguard-go` | Compiled ARMv7 userspace daemon |
| `wireguard-go/` | Upstream WireGuard Go source |
| `wireguard-tools/` | Upstream WireGuard tools source |

## 3. Requirements

### Build host

- Docker Engine and Docker CLI
- Docker support for `linux/arm/v7` (native or emulated)
- Docker support for `linux/amd64`
- GNU Make and Git

The `wg` build uses an Alpine ARMv7 container. The `wireguard-go` build uses an AMD64 Go container to cross-compile for ARMv7.

### Synology NAS

- ARMv7 CPU
- Linux TUN support and `/dev/net/tun`
- `ip` command
- Root privileges for network configuration

Test TUN support:

```sh
ls -l /dev/net/tun
ip tuntap add dev wg-test mode tun
ip link show wg-test
ip link delete wg-test
```

No WireGuard kernel module is required when running `wireguard-go`.

## 4. Build

### Build both binaries

From the repository root:

```sh
make build
```

The current target hierarchy is:

```text
build
  └── build-synology
        ├── build-wg-synology
        └── build-wireguard-go-synology
```

### Build `wg`

```sh
make build-wg-synology
```

The build uses `alpine:3.22` on `linux/arm/v7`, GCC, musl, and static linking. Output:

```text
synology/dist/linux-armv7/wg
```

### Build `wireguard-go`

```sh
make build-wireguard-go-synology
```

Build parameters:

```text
Container platform: linux/amd64
Target OS:          linux
Target architecture: arm
GOARM:              7
CGO_ENABLED:        0
```

Output:

```text
synology/dist/linux-armv7/wireguard-go
```

### Clean

```sh
make clean
```

This removes `synology/dist/linux-armv7/`, but does not necessarily remove object files produced inside `wireguard-tools/src/`.

### Verify artifacts

```sh
file synology/dist/linux-armv7/*
readelf -l synology/dist/linux-armv7/wg | grep INTERP
```

The binaries should be ARM EABI5 executables. The `readelf` command should produce no `INTERP` entry for a fully static `wg` binary.

## 5. Synology installation

Recommended on-device layout:

```text
/volume1/services/wireguard/
├── bin/
│   ├── wg
│   └── wireguard-go
├── config/
│   ├── wg.conf
│   ├── network.env
│   ├── private.key
│   └── public.key
└── scripts/
    └── start.sh
```

Keep service executables and scripts separate from persistent application data under `/volume1/lab-data`.

Create directories on each NAS:

```sh
mkdir -p /volume1/services/wireguard/bin
mkdir -p /volume1/services/wireguard/config
mkdir -p /volume1/services/wireguard/scripts
chmod 700 /volume1/services/wireguard/config
```

Transfer artifacts from the build host (adjust the SSH host and account):

```sh
scp synology/dist/linux-armv7/wg \
  david@nas.vanves:/volume1/services/wireguard/bin/
scp synology/dist/linux-armv7/wireguard-go \
  david@nas.vanves:/volume1/services/wireguard/bin/
```

The destination must exist and be writable by the SSH user. Otherwise, copy to a temporary writable location and move the files as root.

On the NAS:

```sh
chmod 755 /volume1/services/wireguard/bin/wg
chmod 755 /volume1/services/wireguard/bin/wireguard-go
/volume1/services/wireguard/bin/wg --version
/volume1/services/wireguard/bin/wireguard-go --version
```

Copy `synology/start.sh` to `/volume1/services/wireguard/scripts/start.sh` and make it executable:

```sh
chmod 755 /volume1/services/wireguard/scripts/start.sh
```

## 6. WireGuard keys

Each NAS needs a unique key pair. Generate it on the NAS:

```sh
cd /volume1/services/wireguard/config
../bin/wg genkey > private.key
chmod 600 private.key
../bin/wg pubkey < private.key > public.key
cat public.key
```

Register the public key on the Beryl server. Never commit `private.key` or any configuration containing a private key.

## 7. NAS configuration

The startup script loads `config/network.env` and applies `config/wg.conf`.

### NAS Vanves

`network.env`:

```sh
WG_ADDRESS=10.6.6.5/32
WG_NETWORK=10.6.6.0/24
```

`wg.conf`:

```ini
[Interface]
PrivateKey = <NAS_VANVES_PRIVATE_KEY>

[Peer]
PublicKey = <BERYL_PUBLIC_KEY>
Endpoint = 192.168.50.11:51820
AllowedIPs = 10.6.6.0/24
PersistentKeepalive = 25
```

The Beryl endpoint is reachable directly from the NAS Vanves LAN.

### NAS PDC

`network.env`:

```sh
WG_ADDRESS=10.6.6.6/32
WG_NETWORK=10.6.6.0/24
```

`wg.conf`:

```ini
[Interface]
PrivateKey = <NAS_PDC_PRIVATE_KEY>

[Peer]
PublicKey = <BERYL_PUBLIC_KEY>
Endpoint = <BERYL_PUBLIC_ENDPOINT>:51820
AllowedIPs = 10.6.6.0/24
PersistentKeepalive = 25
```

The public endpoint must reach the Beryl server. Ensure UDP port `51820` is forwarded and allowed by upstream routers and firewalls.

Retrieve the Beryl public key on the router:

```sh
wg show wgserver public-key
```

### Beryl peer registration

Register one peer per NAS, using its corresponding public key.

NAS Vanves:

```ini
[Peer]
PublicKey = <NAS_VANVES_PUBLIC_KEY>
AllowedIPs = 10.6.6.5/32
```

NAS PDC:

```ini
[Peer]
PublicKey = <NAS_PDC_PUBLIC_KEY>
AllowedIPs = 10.6.6.6/32
```

Do not reuse an existing peer address. Verify that the Beryl firewall permits the intended forwarding between peers.

## 8. Starting WireGuard

Run as root:

```sh
/volume1/services/wireguard/scripts/start.sh
```

The current script:

1. Sources the NAS-specific network configuration.
2. Creates the userspace WireGuard interface if absent.
3. Applies the peer configuration using `wg setconf`.
4. Assigns the WireGuard IP address.
5. Brings up the interface.
6. Installs the route to the backbone.
7. Displays interface status.

The interface is named `wg-vault`.

The current script sets:

```sh
WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
```

This forces the userspace implementation if `wireguard-go` reports kernel support on the older Synology kernel.

### Verification

```sh
ip link show wg-vault
ip -4 addr show wg-vault
ip route get 10.6.6.2
/volume1/services/wireguard/bin/wg show wg-vault
```

The route to `10.6.6.2` should use `wg-vault`. Check the latest handshake, endpoint, and transfer counters.

Connectivity tests:

```sh
ping 10.6.6.1
ping 10.6.6.2
```

ICMP may be blocked by a firewall; a successful WireGuard handshake does not by itself prove peer-to-peer forwarding works.

**Compatibility note:** Some Synology `ip` implementations do not support `ip addr replace`. If so, adapt `start.sh` to check for an existing address and use `ip addr add` only when necessary. Also ensure the userspace interface's control socket is ready before calling `wg setconf`.

## 9. Routing policy

Example for NAS Vanves:

```text
192.168.50.0/24 -> eth0
10.6.6.0/24     -> wg-vault
0.0.0.0/0       -> 192.168.50.1
```

Do not configure `AllowedIPs = 0.0.0.0/0` unless a full tunnel is intentionally required. The NAS must retain its original default gateway, and existing NFS, SFTPGo, and DSM traffic must continue using the original network paths.

## 10. Automatic startup in Synology DSM

WireGuard can be started with DSM Task Scheduler:

1. Open **Control Panel** → **Task Scheduler**.
2. Create a **Triggered Task** → **User-defined script**.
3. Select **Boot-up**.
4. Run as **root**.
5. Execute:

```sh
/volume1/services/wireguard/scripts/start.sh
```

Ensure `/volume1` is mounted and networking is initialized before starting the script. Add retries where appropriate. A boot-only scheduled task does not supervise or restart `wireguard-go` if it exits unexpectedly; dedicated supervision may be added later.

Planned lifecycle scripts: `stop.sh`, `restart.sh`, and `status.sh`.

## 11. Vault integration

The primary purpose of these NAS WireGuard clients is private communication between Vault Raft nodes.

```text
                  Vault Raft cluster
                         |
              +----------+----------+
              |          |          |
          PC Debian  NAS Vanves   NAS PDC
          10.6.6.2   10.6.6.5    10.6.6.6
              |          |          |
              +----------+----------+
                         |
                  WireGuard backbone
```

Vault uses TCP `8200` for its API and TCP `8201` for cluster communication. The advertised cluster address must be reachable by other Vault nodes, without depending on the public HTTPS ingress.

Example for NAS Vanves:

```hcl
cluster_addr = "https://10.6.6.5:8201"
```

Each Vault node requires its own local Raft storage. Additional nodes must **join the existing cluster** and must **not** independently initialize another cluster.

Recommended startup order:

```text
Synology boot
    |
    v
Volume mounted
    |
    v
Network initialized
    |
    v
WireGuard started
    |
    v
Vault started
    |
    v
Vault joins or reconnects to Raft
```

Vault must tolerate temporary loss of WireGuard connectivity. Do not indefinitely block startup on reachability of the current Raft leader, because the cluster may need to elect a new leader.

## 12. Security

Keep private keys outside Git. Recommended permissions:

```sh
chmod 700 /volume1/services/wireguard/config
chmod 600 /volume1/services/wireguard/config/private.key
chmod 600 /volume1/services/wireguard/config/wg.conf
chmod 600 /volume1/services/wireguard/config/network.env
```

`network.env` is sourced as shell code by `start.sh`, so only trusted administrators should be able to edit it.

Additional precautions:

- Expose only the required WireGuard UDP port.
- Restrict peer-to-peer access with firewall rules where appropriate.
- Never expose Vault Raft port `8201` publicly.
- Avoid exposing DSM management unnecessarily through the tunnel.
- Preserve the NAS default gateway.
- Use unique keys for each NAS.

Suggested `.gitignore`:

```gitignore
# Build artifacts
synology/dist/

# Private keys
*.key
*.private

# Host-specific configuration
wg.conf
network.env

# Logs and temporary files
*.log
*.tmp
```

If upstream sources are tracked as Git submodules, keep generated build objects untracked inside those repositories.

## 13. Troubleshooting

### No handshake

```sh
/volume1/services/wireguard/bin/wg show
```

Check public keys, endpoints, UDP port, NAT forwarding, firewall rules, and peer `AllowedIPs`.

### Handshake succeeds, but ping fails

```sh
ip route get 10.6.6.2
/volume1/services/wireguard/bin/wg show
```

Check the Beryl forwarding policy and the destination firewall.

### Interface does not start

```sh
ls -l /dev/net/tun
/volume1/services/wireguard/bin/wireguard-go --version
ip link show wg-vault
```

### NAS loses network connectivity

```sh
ip route
```

The default route must remain on the original LAN gateway.

## 14. Current status

| Component | Status |
|---|---|
| ARMv7 `wireguard-go` build | Working |
| ARMv7 static `wg` build | Working |
| Synology TUN support | Verified |
| Synology binary execution | Verified |
| Repository Makefile | Implemented |
| Synology startup script | Created |
| NAS Vanves peer configuration | Pending |
| NAS PDC peer configuration | Pending |
| Automatic DSM startup | Pending |
| Vault Raft integration | Pending |

## 15. References

- WireGuard official website: https://www.wireguard.com/
- wireguard-go: https://github.com/WireGuard/wireguard-go
- wireguard-tools: https://git.zx2c4.com/wireguard-tools/
- Synology DSM: https://www.synology.com/

## License

Upstream WireGuard components retain their respective licenses. See their `LICENSE` or `COPYING` files. Define a separate license for this repository's original scripts and build configuration if needed.
