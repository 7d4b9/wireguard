#!/bin/sh
set -eu

BASE=/volume1/homes/admin/wireguard
WG="$BASE/wg"

IFACE=wg-vault

echo "[$(date)] Stopping WireGuard..."

# Vérifier si l'interface existe
if ! ip link show dev "$IFACE" >/dev/null 2>&1; then
    echo "[$(date)] WireGuard already stopped"
    exit 0
fi

# Supprimer uniquement la route gérée par ce service
if ip -4 route show 10.6.6.0/24 dev "$IFACE" | grep -q .; then
    ip -4 route del 10.6.6.0/24 dev "$IFACE"
fi

# Supprimer l'interface TUN.
# wireguard-go détecte sa disparition et termine son processus.
ip link set dev "$IFACE" down
ip link delete dev "$IFACE"

echo "[$(date)] WireGuard stopped"