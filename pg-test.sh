#!/bin/bash
# pg-test.sh — Privacy Guardian v2.1 Diagnostic Suite
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

# ─── Checks ───────────────────────────────────────────────────────────────────

header "nftables Ruleset"

nft list ruleset &>/dev/null \
    && green "nftables is running and ruleset is loaded" \
    || red "nftables ruleset could not be read"

nft list table inet filter &>/dev/null \
    && green "inet filter table exists" \
    || red "inet filter table missing"

nft list chain inet filter privacy_chain &>/dev/null \
    && green "privacy_chain exists in inet filter" \
    || red "privacy_chain missing — DoH/tracker blocking inactive"

nft list table ip6 nat &>/dev/null \
    && green "IPv6 NAT table exists" \
    || yellow "IPv6 NAT table missing — IPv6 DNS may not be redirected"

nft list table ip6 filter &>/dev/null \
    && green "IPv6 filter table exists" \
    || yellow "IPv6 filter table missing — check if IPv6 is disabled via sysctl instead"

header "Dynamic Tracker Set"

TRACKER_COUNT=$(nft list set inet filter tracker_ips 2>/dev/null | grep -c '\.' || echo 0)
if [ "$TRACKER_COUNT" -gt 100 ]; then
    green "tracker_ips set populated ($TRACKER_COUNT entries)"
elif [ "$TRACKER_COUNT" -gt 0 ]; then
    yellow "tracker_ips set has only $TRACKER_COUNT entries — may not have updated yet"
else
    red "tracker_ips set is empty — run update-trackers.sh"
fi

header "DNS Enforcement (NAT Redirect)"

nft list chain ip nat prerouting 2>/dev/null | grep -q "dport 53" \
    && green "IPv4 DNS redirect rule active (port 53 → AdGuard)" \
    || red "IPv4 DNS redirect missing — hardcoded DNS bypasses not blocked"

nft list chain ip6 nat prerouting 2>/dev/null | grep -q "dport 53" \
    && green "IPv6 DNS redirect rule active" \
    || yellow "IPv6 DNS redirect missing"

header "AdGuard Home"

systemctl is-active --quiet AdGuardHome \
    && green "AdGuardHome service is running" \
    || red "AdGuardHome service is NOT running"

curl -sf --max-time 3 http://127.0.0.1:3000 &>/dev/null \
    && green "AdGuard Home UI reachable on port 3000" \
    || red "AdGuard Home UI not reachable on port 3000"

# Check AdGuard is listening on port 53
ss -lnup 2>/dev/null | grep -q ':53 ' \
    && green "AdGuard Home listening on UDP port 53" \
    || red "Nothing listening on UDP port 53 — DNS broken"

header "SSH Rate Limiting"

nft list chain inet filter lan_input 2>/dev/null | grep -q "rate 3/minute" \
    && green "SSH rate limiting rule present" \
    || red "SSH rate limiting missing — Pi vulnerable to brute force"

nft list chain inet filter lan_input 2>/dev/null | grep -q "tcp dport 22.*drop" \
    && green "SSH blocked for non-management IPs" \
    || yellow "SSH may be open to all LAN IPs — verify MGMT_IP restriction"

header "AdGuard UI Restriction"

nft list chain inet filter lan_input 2>/dev/null | grep -q "tcp dport 3000.*drop" \
    && green "AdGuard UI (port 3000) blocked for non-management IPs" \
    || red "AdGuard UI is open to ALL LAN devices — security risk"

header "DoH/DoT Blocking"

nft list chain inet filter privacy_chain 2>/dev/null | grep -q "tcp dport 443.*drop" \
    && green "DoH IP blocking rule active (port 443 to resolver IPs)" \
    || red "DoH blocking missing"

nft list chain inet filter privacy_chain 2>/dev/null | grep -q "dport 853.*drop" \
    && green "DoT blocking rule active (port 853)" \
    || red "DoT blocking missing"

header "Zone-Based Filtering"

nft list set inet filter zone_trusted_clients &>/dev/null \
    && green "Trusted zone set exists" \
    || red "Trusted zone set missing"

nft list set inet filter zone_iot_clients &>/dev/null \
    && green "IoT zone set exists" \
    || red "IoT zone set missing"

nft list set inet filter zone_guest_clients &>/dev/null \
    && green "Guest zone set exists" \
    || red "Guest zone set missing"

nft list chain inet filter zone_trusted_egress &>/dev/null \
    && green "Trusted egress chain exists" \
    || red "Trusted egress chain missing"

nft list chain inet filter zone_iot_egress &>/dev/null \
    && green "IoT egress chain exists" \
    || red "IoT egress chain missing"

nft list chain inet filter zone_guest_egress &>/dev/null \
    && green "Guest egress chain exists" \
    || red "Guest egress chain missing"

nft list chain inet filter privacy_chain 2>/dev/null | grep -q "PG-ZONE-UNKNOWN-DROP" \
    && green "Unknown devices are denied by default" \
    || red "Unknown-zone default deny missing"

nft list set inet filter device_tcp_allow &>/dev/null \
    && green "Per-device TCP allow set exists" \
    || red "Per-device TCP allow set missing"

nft list set inet filter device_udp_allow &>/dev/null \
    && green "Per-device UDP allow set exists" \
    || red "Per-device UDP allow set missing"

nft list set inet filter device_block_all &>/dev/null \
    && green "Per-device block set exists" \
    || red "Per-device block set missing"

header "IPv6 Status"

IPV6_DISABLED=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "unknown")
if [ "$IPV6_DISABLED" = "1" ]; then
    green "IPv6 disabled via sysctl (no IPv6 leak possible)"
elif nft list table ip6 filter &>/dev/null && nft list table ip6 nat &>/dev/null; then
    green "IPv6 managed via nftables (NAT + filtering active)"
else
    red "IPv6 is ENABLED but not properly managed — devices may leak IPv6 traffic"
fi

header "Logging"

journalctl -k --since "1 hour ago" 2>/dev/null | grep -q "PG-" \
    && green "Privacy Guardian firewall log entries found in journal" \
    || yellow "No PG- log entries in last hour — either quiet or logging misconfigured"

header "Cron Jobs"

if grep -q "update-trackers\.sh" /etc/cron.d/privacy-guardian 2>/dev/null; then
    green "Tracker update cron job configured (/etc/cron.d/privacy-guardian)"
else
    yellow "No update-trackers.sh cron job found in /etc/cron.d/privacy-guardian"
fi

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
    echo "All checks passed. Privacy Guardian v2.1 is fully operational."
    exit 0
fi
