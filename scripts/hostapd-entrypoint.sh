#!/bin/bash
# hostapd-entrypoint.sh
# Entrypoint for Privacy Guardian WiFi access point container
# Starts hostapd for Wi-Fi

echo "=== Privacy Guardian WiFi Container (hostapd) ===" 
echo "Container started at $(date)"

# ─── Prepare network interface ──────────────────────────────────────────────
echo "[*] Checking Wi-Fi interface..."

# Wait for wlan0 to be available
WAIT_COUNT=0
MAX_WAIT=15
while ! ip link show wlan0 2>/dev/null && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    echo "[*] Waiting for wlan0 interface... ($WAIT_COUNT/$MAX_WAIT)"
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if ! ip link show wlan0 2>/dev/null; then
    echo "[!] ERROR: wlan0 interface not found after waiting"
    echo "[*] Available interfaces:"
    ip link show
    echo "[!] Keeping container alive for debugging..."
    tail -f /dev/null
fi

echo "[✓] wlan0 interface found"

# ─── Bring up interface ─────────────────────────────────────────────────────
echo "[*] Bringing up wlan0 interface..."
ip link set wlan0 up 2>&1 || true
sleep 2

# ─── Ensure hostapd directories exist ──────────────────────────────────────
mkdir -p /etc/hostapd /var/log/privacy-guardian /var/run/hostapd
echo "[*] Directories created"

# ─── Verify configuration ──────────────────────────────────────────────────
if [ ! -f /etc/hostapd/hostapd.conf ]; then
    echo "[!] ERROR: /etc/hostapd/hostapd.conf not found"
    echo "[!] Available files:"
    ls -la /etc/hostapd/ || true
    tail -f /dev/null
fi

echo "[✓] hostapd.conf found"
echo "[*] Configuration preview:"
head -15 /etc/hostapd/hostapd.conf

# ─── Start hostapd ──────────────────────────────────────────────────────────
echo "[*] Starting hostapd..."
echo "[*] Running: hostapd -d /etc/hostapd/hostapd.conf"

# Run hostapd directly with output capture
hostapd -d /etc/hostapd/hostapd.conf 2>&1 | tee -a /var/log/privacy-guardian/hostapd.log &
HOSTAPD_PID=$!

echo "[*] hostapd started with PID $HOSTAPD_PID"
sleep 3

# Check if process is still running
if kill -0 $HOSTAPD_PID 2>/dev/null; then
    echo "[✓] hostapd is running successfully"
    wait $HOSTAPD_PID
else
    echo "[!] helpastapd exited immediately"
    echo "[*] Recent log output:"
    tail -20 /var/log/privacy-guardian/hostapd.log 2>/dev/null || echo "No log file"
    tail -f /dev/null
fi
