#!/bin/bash
# update-doh-ips.sh — Privacy Guardian v2.1
# Refreshes the known public DoH resolver IP list in nftables.conf
# Run manually every 1-2 months or when a resolver updates their IP ranges.
#
# Sources checked:
#   - Cloudflare: https://www.cloudflare.com/ips/
#   - Google: https://developers.google.com/speed/public-dns/docs/doh
#   - Quad9: https://www.quad9.net/service/service-addresses-and-features
#   - NextDNS, ControlD, AdGuard: checked from their docs
#
# This script resolves the primary hostnames of each resolver and compares
# against the current nftables.conf — you review and merge manually.

set -euo pipefail

LOG_TAG="privacy-guardian-doh"
NFTABLES_CONF="/etc/nftables.conf"
OUTFILE="/tmp/doh-ip-refresh-$(date +%Y%m%d).txt"

log() { echo "[$(date '+%H:%M:%S')] $1"; }
warn() { echo "[WARN] $1" >&2; }

RESOLVERS=(
    # Cloudflare
    "one.one.one.one"
    "one.zero.zero.one"
    # Google
    "dns.google"
    # Quad9
    "dns.quad9.net"
    "dns9.quad9.net"
    # OpenDNS
    "dns.opendns.com"
    # AdGuard
    "dns.adguard-dns.com"
    "dns-unfiltered.adguard.com"
    # NextDNS
    "dns.nextdns.io"
    # ControlD
    "freedns.controld.com"
    # CleanBrowsing
    "security-filter-dns.cleanbrowsing.org"
    # Mullvad
    "dns.mullvad.net"
)

log "Resolving DoH resolver IPs..."
echo "# DoH IP refresh — $(date)" > "$OUTFILE"
echo "# Review these IPs and update the DOH_IPS define in nftables.conf" >> "$OUTFILE"
echo "" >> "$OUTFILE"

for host in "${RESOLVERS[@]}"; do
    ipv4=$(dig +short "$host" A 2>/dev/null | grep -E '^[0-9.]+$' | head -3 || echo "")
    ipv6=$(dig +short "$host" AAAA 2>/dev/null | grep -E '^[0-9a-f:]+$' | head -3 || echo "")

    echo "# $host" >> "$OUTFILE"
    [ -n "$ipv4" ] && echo "$ipv4" >> "$OUTFILE" || warn "No IPv4 for $host"
    [ -n "$ipv6" ] && echo "$ipv6" >> "$OUTFILE" || true
    echo "" >> "$OUTFILE"
    log "  $host → IPv4: ${ipv4:-none}  IPv6: ${ipv6:-none}"
done

log ""
log "Results written to: $OUTFILE"
log ""
log "Next steps:"
log "  1. Review $OUTFILE"
log "  2. Compare against current DOH_IPS in $NFTABLES_CONF"
log "  3. Add any new IPs to both DOH_IPS and DOH_IPS6 defines"
log "  4. Run: sudo nft -f $NFTABLES_CONF"
log "  5. Verify: sudo nft list ruleset | grep -A5 'DOH'"
