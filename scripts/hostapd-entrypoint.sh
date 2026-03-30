#!/bin/bash
# hostapd-entrypoint.sh
# Entrypoint for Privacy Guardian WiFi access point container
# Starts hostapd for Wi-Fi

set -euo pipefail

echo "=== Privacy Guardian WiFi Container (hostapd) ==="
echo "Container started at $(date)"

# ─── Prepare network interface ──────────────────────────────────────────────
echo "[*] Checking Wi-Fi interface..."

# Wait for wlan0 to be available
WAIT_COUNT=0
MAX_WAIT=15
while ! ip link show wlan0 &>/dev/null && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    echo "[*] Waiting for wlan0 interface... ($WAIT_COUNT/$MAX_WAIT)"
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if ! ip link show wlan0 &>/dev/null; then
    echo "[!] ERROR: wlan0 interface not found after waiting"
    echo "[*] Available interfaces:"
    ip link show
    exit 1
fi

echo "[✓] wlan0 interface found"

# ─── Bring up interface ─────────────────────────────────────────────────────
echo "[*] Bringing up wlan0 interface..."
ip link set wlan0 up || true

# ─── Ensure hostapd directories exist ──────────────────────────────────────
mkdir -p /etc/hostapd /var/log/privacy-guardian /var/run/hostapd

# ─── Start hostapd ──────────────────────────────────────────────────────────
echo "[*] Starting hostapd..."

if [ -f /etc/hostapd/hostapd.conf ]; then
    echo "[*] Using configuration from /etc/hostapd/hostapd.conf"
    
    # Run hostapd in foreground (-d flag)
    # Note: hostapd in container may require extra privileges
    exec hostapd -f /var/log/privacy-guardian/hostapd.log \
        -K \
        -d \
        /etc/hostapd/hostapd.conf
else
    echo "[!] ERROR: /etc/hostapd/hostapd.conf not found"
    exit 1
fi
