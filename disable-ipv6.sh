#!/bin/bash
# disable-ipv6.sh — Privacy Guardian v2.1
# ALTERNATIVE to full IPv6 support: completely disable IPv6 on the Pi
# and block it from LAN devices, closing the IPv6 leak vector entirely.
#
# Use this if you do NOT want to manage IPv6 NAT/routing complexity.
# Trade-off: devices cannot use IPv6 at all (most sites work fine over IPv4).
#
# To use full IPv6 support instead, use the nftables.conf ip6 tables
# and configure your LAN prefix — do NOT run this script.

set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "Disabling IPv6 on Privacy Guardian..."

# ── Disable IPv6 in kernel ─────────────────────────────────────────────────
cat >> /etc/sysctl.conf << 'EOF'

# Privacy Guardian — disable IPv6 to prevent bypass of privacy rules
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p
log "IPv6 disabled in kernel via sysctl"

# ── Block IPv6 at firewall level (belt-and-suspenders) ──────────────────────
# Even with sysctl disabled, add nftables rules as a fallback
cat >> /etc/nftables.conf << 'EOF'

# ── IPv6 BLOCK TABLE (when not using full IPv6 support) ───────────────────
table ip6 filter {
    chain input   { type filter hook input   priority 0; policy drop; }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output  { type filter hook output  priority 0; policy drop; }
}
EOF

log "IPv6 drop rules added to nftables.conf"

# ── Block IPv6 RA from WAN (prevents ISP from assigning IPv6 to Pi) ─────────
# This is handled by the policy drop on ip6 filter input above

# ── Disable IPv6 in AdGuard Home ─────────────────────────────────────────────
log ""
log "ACTION REQUIRED: In AdGuard Home settings:"
log "  Settings → DNS Settings → Upstream DNS → uncheck 'Use IPv6'"
log "  Settings → Network → uncheck 'Enable IPv6'"
log ""

log "IPv6 disable complete. Run: sudo nft -f /etc/nftables.conf && sudo sysctl -p"
log "Then reboot and verify with: ip addr | grep inet6"
