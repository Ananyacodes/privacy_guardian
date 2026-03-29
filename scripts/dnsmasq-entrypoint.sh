#!/bin/bash
# dnsmasq-entrypoint.sh
# Entrypoint for Privacy Guardian DHCP container
# Starts dnsmasq DHCP server

set -euo pipefail

echo "=== Privacy Guardian DHCP Container (dnsmasq) ==="
echo "Container started at $(date)"

# ─── Prepare network interface ──────────────────────────────────────────────
echo "[*] Configuring network interfaces..."

# Wait for wlan0 to be available (may take a moment on Pi)
WAIT_COUNT=0
MAX_WAIT=10
while ! ip link show wlan0 &>/dev/null && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    echo "[*] Waiting for wlan0 interface... ($WAIT_COUNT/$MAX_WAIT)"
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if ip link show wlan0 &>/dev/null; then
    echo "[✓] wlan0 interface found"
    
    # Set interface IP if not already set
    if ! ip addr show wlan0 | grep -q "192.168.4.1"; then
        echo "[*] Configuring wlan0 IP address..."
        ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true
    fi
else
    echo "[!] WARNING: wlan0 interface not found"
fi

# Check for eth0
if ip link show eth0 &>/dev/null; then
    echo "[✓] eth0 interface found"
else
    echo "[!] WARNING: eth0 interface not found"
fi

# ─── Ensure dnsmasq directories exist ───────────────────────────────────────
mkdir -p /var/lib/misc /var/log/privacy-guardian

# ─── Start dnsmasq ──────────────────────────────────────────────────────────
echo "[*] Starting dnsmasq DHCP server..."

# Note: dnsmasq with -d flag disables daemon mode and stays in foreground
# This is necessary for docker containers
if [ -f /etc/dnsmasq.conf ]; then
    echo "[*] Using configuration from /etc/dnsmasq.conf"
    # Run dnsmasq in foreground
    exec dnsmasq -d \
        --conf-file=/etc/dnsmasq.conf \
        --log-facility=/var/log/privacy-guardian/dnsmasq.log \
        --user=root
else
    echo "[!] ERROR: /etc/dnsmasq.conf not found"
    exit 1
fi
