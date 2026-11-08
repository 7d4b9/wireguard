#!/bin/sh
set -eu

BASE=/volume1/services/wireguard

WG="$BASE/bin/wg"
WG_GO="$BASE/bin/wireguard-go"

CONF="$BASE/config/wg.conf"

IFACE=wg-vault

# Paramètres spécifiques à chaque NAS
. "$BASE/config/network.env"

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1 \
        "$WG_GO" "$IFACE"
fi

"$WG" setconf "$IFACE" "$CONF"

ip addr replace "$WG_ADDRESS" dev "$IFACE"
ip link set dev "$IFACE" mtu 1420 up

ip route replace "$WG_NETWORK" dev "$IFACE"

echo "WireGuard started"

"$WG" show "$IFACE"