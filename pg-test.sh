#!/bin/bash
# pg-test.sh — Privacy Guardian v3.0 Diagnostic Suite (Docker)
# Run this after deployment to verify all protections are active.
# Safe to run repeatedly — read-only checks, no changes made.

set -uo pipefail

PASS=0
FAIL=0
WARN=0

# ─── Output helpers ───────────────────────────────────────────────────────────
green()  { echo -e "\033[32m[PASS]\033[0m $1"; PASS=$((PASS+1)); }
red()    { echo -e "\033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL+1)); }
yellow() { echo -e "\033[33m[WARN]\033[0m $1"; WARN=$((WARN+1)); }
header() { echo -e "\n\033[1m── $1 ──\033[0m"; }

# Detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Check if we're in the right directory
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    red "docker-compose.yml not found in $PROJECT_DIR"
    red "Please run this script from the Privacy Guardian project root directory"
    exit 1
fi

# ─── Checks ───────────────────────────────────────────────────────────────────

header "Docker Status"

# Check Docker daemon
docker ps -q > /dev/null 2>&1 \
    && green "Docker daemon is running" \
    || { red "Docker daemon not running"; exit 1; }

# Check Docker Compose installation
docker compose version > /dev/null 2>&1 \
    && green "Docker Compose is available" \
    || { red "Docker Compose not installed"; exit 1; }

header "Container Status"

# Check all containers
for container in pg-adguard pg-dnsmasq pg-firewall pg-hostapd; do
    if docker compose ps "$container" 2>/dev/null | grep -q "Up"; then
        green "$container container is running"
    elif docker compose ps "$container" 2>/dev/null | grep -q "Exited"; then
        red "$container container is NOT running"
    else
        yellow "$container container status unknown (may not be configured)"
    fi
done

header "nftables Ruleset (via firewall container)"

docker compose exec -T pg-firewall nft list ruleset &>/dev/null \
    && green "nftables is running and ruleset is loaded" \
    || red "nftables ruleset could not be read"

docker compose exec -T pg-firewall nft list table inet filter &>/dev/null \
    && green "inet filter table exists" \
    || red "inet filter table missing"

docker compose exec -T pg-firewall nft list chain inet filter input &>/dev/null \
    && green "input chain exists in inet filter" \
    || red "input chain missing — firewall rules not active"

header "Dynamic Tracker Set"

TRACKER_COUNT=$(docker compose exec -T pg-firewall nft list set inet filter tracker_ips 2>/dev/null | grep -c '\.' || echo 0)
if [ "$TRACKER_COUNT" -gt 100 ]; then
    green "tracker_ips set populated ($TRACKER_COUNT entries)"
elif [ "$TRACKER_COUNT" -gt 0 ]; then
    yellow "tracker_ips set has only $TRACKER_COUNT entries — may not have updated yet"
else
    red "tracker_ips set is empty — blocking may not be working"
fi

header "DNS Enforcement"

docker compose exec -T pg-firewall nft list chain ip nat prerouting 2>/dev/null | grep -q "dport 53" \
    && green "DNS redirect rule active (port 53 → AdGuard)" \
    || red "DNS redirect missing — hardcoded DNS bypasses not blocked"

header "AdGuard Home"

docker compose exec -T pg-adguard ps aux 2>/dev/null | grep -q "[A]dGuardHome" \
    && green "AdGuardHome process is running" \
    || red "AdGuardHome process is NOT running"

docker compose exec -T pg-adguard curl -sf --max-time 3 http://127.0.0.1:3000 &>/dev/null \
    && green "AdGuard Home UI reachable on port 3000" \
    || red "AdGuard Home UI not reachable on port 3000"

# Check AdGuard is listening on port 53
docker compose exec -T pg-adguard sh -c "netstat -lnup 2>/dev/null | grep -q ':53 '" &>/dev/null \
    && green "AdGuard Home listening on UDP port 53" \
    || red "Nothing listening on UDP port 53 — DNS broken"

header "DHCP Server (dnsmasq)"

docker compose exec -T pg-dnsmasq ps aux 2>/dev/null | grep -q "[d]nsmasq" \
    && green "dnsmasq process is running" \
    || red "dnsmasq is NOT running — DHCP server unavailable"

# Check DHCP leases
LEASE_COUNT=$(docker compose exec -T pg-dnsmasq wc -l < /var/lib/misc/dnsmasq.leases 2>/dev/null || echo 0)
if [ "$LEASE_COUNT" -gt 0 ]; then
    green "DHCP leases found ($LEASE_COUNT active)"
else
    yellow "No DHCP leases recorded yet (may be normal on fresh setup)"
fi

header "Firewall IP Forwarding"

# Check if IP forwarding is enabled on host
if [ -f /proc/sys/net/ipv4/ip_forward ]; then
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
        green "IPv4 forwarding enabled"
    else
        red "IPv4 forwarding disabled — router cannot function"
    fi
else
    yellow "Cannot check IPv4 forwarding status"
fi

header "Firewall Capabilities"

docker inspect pg-firewall 2>&1 | grep -q "NET_ADMIN" \
    && green "Firewall container has NET_ADMIN capability" \
    || yellow "NET_ADMIN capability check inconclusive"

docker inspect pg-dnsmasq 2>&1 | grep -q "NET_ADMIN" \
    && green "DHCP container has NET_ADMIN capability" \
    || yellow "NET_ADMIN capability check inconclusive"

header "Network Interfaces"

if ip link show wlan0 &>/dev/null; then
    green "wlan0 interface exists"
    WLAN_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet )\S+' || echo "not configured")
    if [ "$WLAN_IP" != "not configured" ]; then
        green "wlan0 has IP address: $WLAN_IP"
    else
        yellow "wlan0 exists but no IP configured"
    fi
else
    red "wlan0 interface not found — WiFi may not be functional"
fi

if ip link show eth0 &>/dev/null; then
    green "eth0 interface exists"
else
    warning "eth0 interface not found — check if this is the WAN interface name on your platform"
fi

header "Volumes and Persistence"

docker volume ls | grep -q "privacy-guardian_adguard-work" \
    && green "AdGuard volume exists" \
    || yellow "AdGuard volume may not be created yet"

docker volume ls | grep -q "privacy-guardian_dnsmasq-leases" \
    && green "DHCP leases volume exists" \
    || yellow "DHCP volume may not be created yet"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
echo -e "\033[32mPASS: $PASS\033[0m  \033[31mFAIL: $FAIL\033[0m  \033[33mWARN: $WARN\033[0m"
echo "─────────────────────────────────────"

if [ $FAIL -gt 0 ]; then
    echo "Critical issues found. Review FAIL items above before relying on Privacy Guardian."
    exit 1
elif [ $WARN -gt 0 ]; then
    echo "Warnings found. System is functional but review WARN items for full protection."
    exit 0
else
    echo "All checks passed. Privacy Guardian v3.0 is fully operational."
    exit 0
fi
