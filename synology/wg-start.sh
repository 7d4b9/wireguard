#!/bin/sh
set -eu

BASE=/volume1/homes/admin/wireguard

WG="$BASE/wg"
WG_GO="$BASE/wireguard-go"
CONF="$BASE/wg.conf"

IFACE=wg-vault
MTU=1420

echo "[$(date)] Starting WireGuard..."

# Récupération de l'adresse de l'interface
ADDRESS=$(awk '
    /^[[:space:]]*Address[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, "")
        gsub(/[[:space:]]/, "")
        print
        exit
    }
' "$CONF")

if [ -z "$ADDRESS" ]; then
    echo "Missing Address in $CONF" >&2
    exit 1
fi

# Création de l'interface userspace
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1 \
        "$WG_GO" "$IFACE"
fi

# Conversion de la configuration wg-quick en configuration wg
TMP_CONF=$(mktemp)
trap 'rm -f "$TMP_CONF"' EXIT HUP INT TERM

awk '
    /^[[:space:]]*(Address|DNS|MTU|Table|PreUp|PostUp|PreDown|PostDown|SaveConfig)[[:space:]]*=/ {
        next
    }
    { print }
' "$CONF" > "$TMP_CONF"

# Attente de disponibilité de l'interface WireGuard
i=0
until "$WG" show "$IFACE" >/dev/null 2>&1; do
    i=$((i + 1))

    if [ "$i" -ge 10 ]; then
        echo "WireGuard interface unavailable" >&2
        exit 1
    fi

    sleep 1
done

"$WG" setconf "$IFACE" "$TMP_CONF"

# Configuration IP
if ! ip -4 addr show dev "$IFACE" | grep -Fq "$ADDRESS"; then
    ip addr add "$ADDRESS" dev "$IFACE"
fi

ip link set dev "$IFACE" mtu "$MTU" up

# Routage du backbone uniquement
ip route replace 10.6.6.0/24 dev "$IFACE"

echo "[$(date)] WireGuard started"

"$WG" show "$IFACE"