#!/bin/bash
# firewall-entrypoint.sh
# Entrypoint for Privacy Guardian firewall container
# Loads nftables rules and enables IP forwarding

set -euo pipefail

echo "=== Privacy Guardian Firewall Container ==="
echo "Container started at $(date)"

# ─── Enable IP Forwarding ───────────────────────────────────────────────────
echo "[*] Enabling IP forwarding..."

# IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.rp_filter=1 > /dev/null 2>&1 || true
sysctl -w net.ipv4.conf.eth0.rp_filter=1 > /dev/null 2>&1 || true
sysctl -w net.ipv4.conf.wlan0.rp_filter=1 > /dev/null 2>&1 || true

# ICMP hardening
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 > /dev/null 2>&1 || true
sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 > /dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.accept_redirects=0 > /dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.send_redirects=0 > /dev/null 2>&1 || true

# IPv6 forwarding (if IPv6 is not disabled)
if [ -d /proc/sys/net/ipv6 ]; then
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.all.accept_redirects=0 > /dev/null 2>&1 || true
fi

echo "[✓] IP forwarding enabled"

# ─── Load nftables ruleset ──────────────────────────────────────────────────
echo "[*] Loading nftables ruleset..."

if [ -f /etc/nftables.conf ]; then
    if nft -f /etc/nftables.conf 2>&1 | grep -i error; then
        echo "[!] WARNING: nftables load had errors (non-fatal)"
    else
        echo "[✓] nftables ruleset loaded successfully"
    fi
else
    echo "[!] WARNING: /etc/nftables.conf not found"
fi

# ─── Display loaded ruleset ─────────────────────────────────────────────────
echo ""
echo "[*] Current nftables ruleset:"
nft list ruleset | head -30
echo ""

# ─── Keep container running ─────────────────────────────────────────────────
echo "[✓] Firewall container ready"
echo "Container will remain running. Use 'docker logs' to view output."
echo ""

# Sleep indefinitely to keep container alive
exec tail -f /dev/null
