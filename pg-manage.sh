#!/bin/bash
# pg-manage.sh — Privacy Guardian v2.1 Management CLI
# A single tool for all ongoing maintenance tasks
#
# Usage: sudo pg-manage.sh <command>
#
# Commands:
#   status          Show status of all services
#   logs            Tail live firewall + AdGuard logs
#   blocked         Show recently blocked domains and IPs
#   zone-logs [h]   Show zone drop logs (default 24h) for tuning
#   update          Run tracker + DoH IP updates
#   reload          Reload nftables ruleset without rebooting
#   whitelist <domain>   Add a domain to AdGuard Home whitelist
#   allow-device <ip> <tcp|udp> <port>   Allow one device to use one outbound port
#   unallow-device <ip> <tcp|udp> <port> Remove one device-specific outbound allow
#   block-device <ip>   Block all outbound traffic for one device
#   unblock-device <ip> Remove explicit per-device block
#   device-rules    Show active per-device firewall overrides
#   ban <ip>        Manually add an IP to tracker_ips blocklist
#   unban <ip>      Remove an IP from tracker_ips blocklist
#   clients         Show connected devices and their IPs
#   backup          Backup all config files
#   restore <file>  Restore configs from backup

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${BOLD}${BLUE}── $1 ──${NC}"; }
ok()     { echo -e "${GREEN}●${NC} $1"; }
fail()   { echo -e "${RED}●${NC} $1"; }
warn()   { echo -e "${YELLOW}●${NC} $1"; }

valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    awk -F. 'NF==4 {for (i=1; i<=4; i++) if ($i<0 || $i>255) exit 1; exit 0} {exit 1}' <<< "$ip"
}

valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

COMMAND="${1:-help}"

case "$COMMAND" in

# ─── STATUS ──────────────────────────────────────────────────────────────────
status)
    header "Privacy Guardian v2.1 — Service Status"

    for svc in hostapd dnsmasq nftables AdGuardHome fail2ban; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc: running"
        else
            fail "$svc: STOPPED"
        fi
    done

    header "Network"
    echo "  Pi IP (wlan0): $(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet )\S+' || echo 'not configured')"
    echo "  WAN IP (eth0): $(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet )\S+' || echo 'not configured')"
    echo "  Connected devices: $(cat /var/lib/misc/dnsmasq.leases 2>/dev/null | wc -l) active DHCP leases"

    header "Firewall"
    echo "  tracker_ips entries: $(nft list set inet filter tracker_ips 2>/dev/null | grep -c '\.' || echo 0)"
    echo "  Active connections: $(nft list ruleset 2>/dev/null | grep -c 'ct state established' || echo 'unknown')"

    header "AdGuard Home (last 24h)"
    # Query AdGuard Home stats API
    STATS=$(curl -sf --max-time 3 http://127.0.0.1:3000/control/stats 2>/dev/null || echo '{}')
    if [ "$STATS" != '{}' ]; then
        echo "  DNS queries:   $(echo "$STATS" | grep -oP '"num_dns_queries":\K[0-9]+'  || echo 'N/A')"
        echo "  Blocked:       $(echo "$STATS" | grep -oP '"num_blocked_filtering":\K[0-9]+' || echo 'N/A')"
        echo "  Block rate:    $(echo "$STATS" | grep -oP '"num_replaced_safebrowsing":\K[0-9]+' || echo 'N/A')"
    else
        warn "AdGuard stats API not reachable"
    fi
    ;;

# ─── LOGS ────────────────────────────────────────────────────────────────────
logs)
    header "Live Logs (Ctrl+C to stop)"
    journalctl -f -k --grep="PG-" \
        & journalctl -f -u AdGuardHome \
        & journalctl -f -u hostapd \
        & wait
    ;;

# ─── BLOCKED ─────────────────────────────────────────────────────────────────
blocked)
    header "Recently Blocked (last 100 entries)"
    echo ""
    echo "  ── Firewall drops (nftables) ──"
    journalctl -k --since "24 hours ago" --grep="PG-" --no-pager 2>/dev/null \
        | grep -oP 'PG-\S+.*DST=\S+' \
        | sort | uniq -c | sort -rn \
        | head -20 \
        || echo "  No firewall drops logged"

    echo ""
    echo "  ── DNS blocks (AdGuard — query log) ──"
    # AdGuard Home query log via API
    curl -sf --max-time 5 "http://127.0.0.1:3000/control/querylog?limit=50" 2>/dev/null \
        | grep -oP '"question":{"name":"\K[^"]+(?=".*"status":"Filtered")' \
        | sort | uniq -c | sort -rn \
        | head -20 \
        || echo "  Could not reach AdGuard query log API"
    ;;

# ─── ZONE LOGS ───────────────────────────────────────────────────────────────
zone-logs)
    HOURS="${2:-24}"
    [[ "$HOURS" =~ ^[0-9]+$ ]] || { fail "Hours must be a number"; exit 1; }

    header "Zone Drop Logs (last ${HOURS}h)"
    echo ""
    echo "  ── Top blocked destinations by zone ──"
    journalctl -k --since "${HOURS} hours ago" --no-pager 2>/dev/null \
        | grep -E 'PG-(TRUSTED|IOT|GUEST|ZONE-UNKNOWN)-DROP' \
        | grep -oP 'PG-[A-Z-]+-DROP:.*DST=\S+.*DPT=\S+' \
        | sed -E 's/.*(PG-[A-Z-]+-DROP:).*DST=([^ ]+).*DPT=([^ ]+).*/\1 DST=\2 DPT=\3/' \
        | sort | uniq -c | sort -rn | head -30 \
        || echo "  No zone drop logs found"

    echo ""
    echo "  Tip: only allow per-device ports after confirming repeated legitimate drops."
    ;;

# ─── UPDATE ───────────────────────────────────────────────────────────────────
update)
    header "Running All Updates"
    echo ""
    info() { echo -e "${BLUE}[→]${NC} $1"; }

    info "Updating tracker IP blocklist..."
    /usr/local/bin/update-trackers.sh

    info "Checking DoH resolver IPs for changes..."
    /usr/local/bin/update-doh-ips.sh

    info "Updating system packages..."
    apt-get update -qq && apt-get upgrade -y -qq

    echo ""
    ok "All updates complete"
    ;;

# ─── RELOAD ──────────────────────────────────────────────────────────────────
reload)
    header "Reloading nftables Ruleset"
    nft --check -f /etc/nftables.conf || { fail "Ruleset has errors — not applied"; exit 1; }
    nft -f /etc/nftables.conf
    ok "nftables ruleset reloaded"
    ;;

# ─── ALLOW DEVICE ────────────────────────────────────────────────────────────
allow-device)
    IP="${2:-}"
    PROTO="${3:-}"
    PORT="${4:-}"
    [ -n "$IP" ] && [ -n "$PROTO" ] && [ -n "$PORT" ] || { echo "Usage: pg-manage.sh allow-device <ip> <tcp|udp> <port>"; exit 1; }
    valid_ipv4 "$IP" || { fail "Invalid IPv4: $IP"; exit 1; }
    valid_port "$PORT" || { fail "Invalid port: $PORT"; exit 1; }
    [[ "$PROTO" = "tcp" || "$PROTO" = "udp" ]] || { fail "Protocol must be tcp or udp"; exit 1; }

    header "Allow Device Exception"
    if [ "$PROTO" = "tcp" ]; then
        nft add element inet filter device_tcp_allow "{ $IP . $PORT }" || { fail "Failed to add TCP allow"; exit 1; }
    else
        nft add element inet filter device_udp_allow "{ $IP . $PORT }" || { fail "Failed to add UDP allow"; exit 1; }
    fi

    ok "Allowed $IP -> $PROTO/$PORT"
    warn "Runtime change only. Persist by adding the element to the matching set in /etc/nftables.conf"
    ;;

# ─── UNALLOW DEVICE ──────────────────────────────────────────────────────────
unallow-device)
    IP="${2:-}"
    PROTO="${3:-}"
    PORT="${4:-}"
    [ -n "$IP" ] && [ -n "$PROTO" ] && [ -n "$PORT" ] || { echo "Usage: pg-manage.sh unallow-device <ip> <tcp|udp> <port>"; exit 1; }
    valid_ipv4 "$IP" || { fail "Invalid IPv4: $IP"; exit 1; }
    valid_port "$PORT" || { fail "Invalid port: $PORT"; exit 1; }
    [[ "$PROTO" = "tcp" || "$PROTO" = "udp" ]] || { fail "Protocol must be tcp or udp"; exit 1; }

    header "Remove Device Exception"
    if [ "$PROTO" = "tcp" ]; then
        nft delete element inet filter device_tcp_allow "{ $IP . $PORT }" || { fail "TCP allow not found"; exit 1; }
    else
        nft delete element inet filter device_udp_allow "{ $IP . $PORT }" || { fail "UDP allow not found"; exit 1; }
    fi

    ok "Removed allow $IP -> $PROTO/$PORT"
    ;;

# ─── BLOCK DEVICE ────────────────────────────────────────────────────────────
block-device)
    IP="${2:-}"
    [ -n "$IP" ] || { echo "Usage: pg-manage.sh block-device <ip>"; exit 1; }
    valid_ipv4 "$IP" || { fail "Invalid IPv4: $IP"; exit 1; }

    header "Blocking Device"
    nft add element inet filter device_block_all "{ $IP }" || { fail "Failed to block $IP"; exit 1; }
    ok "All outbound traffic blocked for $IP"
    ;;

# ─── UNBLOCK DEVICE ──────────────────────────────────────────────────────────
unblock-device)
    IP="${2:-}"
    [ -n "$IP" ] || { echo "Usage: pg-manage.sh unblock-device <ip>"; exit 1; }
    valid_ipv4 "$IP" || { fail "Invalid IPv4: $IP"; exit 1; }

    header "Unblocking Device"
    nft delete element inet filter device_block_all "{ $IP }" || { fail "Device $IP is not currently blocked"; exit 1; }
    ok "Removed explicit block for $IP"
    ;;

# ─── DEVICE RULES ────────────────────────────────────────────────────────────
device-rules)
    header "Per-Device Overrides"
    echo ""
    echo "  device_block_all:"
    nft list set inet filter device_block_all 2>/dev/null || echo "  (set missing)"
    echo ""
    echo "  device_tcp_allow:"
    nft list set inet filter device_tcp_allow 2>/dev/null || echo "  (set missing)"
    echo ""
    echo "  device_udp_allow:"
    nft list set inet filter device_udp_allow 2>/dev/null || echo "  (set missing)"
    ;;

# ─── WHITELIST ────────────────────────────────────────────────────────────────
whitelist)
    DOMAIN="${2:-}"
    [ -z "$DOMAIN" ] && { echo "Usage: pg-manage.sh whitelist <domain>"; exit 1; }
    header "Whitelisting: $DOMAIN"
    # Add to AdGuard Home via API
    RESULT=$(curl -sf --max-time 5 \
        -X POST "http://127.0.0.1:3000/control/filtering/add_url" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"Manual whitelist\",\"url\":\"@@||${DOMAIN}^\"}" \
        2>/dev/null)
    ok "Domain '$DOMAIN' added to AdGuard whitelist"
    echo "  Verify in AdGuard Home UI → Filters → Custom Filtering Rules"
    ;;

# ─── BAN ─────────────────────────────────────────────────────────────────────
ban)
    IP="${2:-}"
    [ -z "$IP" ] && { echo "Usage: pg-manage.sh ban <ip>"; exit 1; }
    header "Banning IP: $IP"
    nft add element inet filter tracker_ips "{ $IP }" || { fail "Failed to add $IP"; exit 1; }
    ok "IP $IP added to tracker_ips blocklist (active immediately)"
    warn "This is temporary — survives until next tracker update or reboot"
    warn "To make permanent: add to /etc/nftables.conf tracker_ips set"
    ;;

# ─── UNBAN ───────────────────────────────────────────────────────────────────
unban)
    IP="${2:-}"
    [ -z "$IP" ] && { echo "Usage: pg-manage.sh unban <ip>"; exit 1; }
    header "Removing IP from blocklist: $IP"
    nft delete element inet filter tracker_ips "{ $IP }" || { fail "IP $IP not found in tracker_ips"; exit 1; }
    ok "IP $IP removed from tracker_ips"
    ;;

# ─── CLIENTS ─────────────────────────────────────────────────────────────────
clients)
    header "Connected Devices"
    echo ""
    printf "  %-18s %-20s %-20s %s\n" "IP Address" "MAC Address" "Hostname" "Lease Expires"
    printf "  %-18s %-20s %-20s %s\n" "──────────" "───────────" "────────" "─────────────"
    while IFS=' ' read -r expiry mac ip hostname _; do
        if [ "$expiry" = "0" ]; then
            expires="static"
        else
            expires=$(date -d "@$expiry" '+%H:%M %d/%m' 2>/dev/null || echo "unknown")
        fi
        printf "  %-18s %-20s %-20s %s\n" "$ip" "$mac" "$hostname" "$expires"
    done < /var/lib/misc/dnsmasq.leases 2>/dev/null || echo "  No DHCP leases found"
    ;;

# ─── BACKUP ──────────────────────────────────────────────────────────────────
backup)
    BACKUP_DIR="/var/backups/privacy-guardian"
    BACKUP_FILE="$BACKUP_DIR/pg-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    mkdir -p "$BACKUP_DIR"

    header "Backing Up Configuration"
    tar -czf "$BACKUP_FILE" \
        /etc/nftables.conf \
        /etc/hostapd/hostapd.conf \
        /etc/dnsmasq.conf \
        /etc/dhcpcd.conf \
        /etc/sysctl.d/99-privacy-guardian.conf \
        /opt/AdGuardHome/AdGuardHome.yaml \
        /etc/fail2ban/jail.d/privacy-guardian.conf \
        /usr/local/bin/update-trackers.sh \
        /usr/local/bin/pg-test.sh \
        2>/dev/null

    ok "Backup saved: $BACKUP_FILE"
    echo "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    ;;

# ─── RESTORE ─────────────────────────────────────────────────────────────────
restore)
    BACKUP_FILE="${2:-}"
    [ -z "$BACKUP_FILE" ] && { echo "Usage: pg-manage.sh restore <backup-file>"; exit 1; }
    [ -f "$BACKUP_FILE" ] || { fail "File not found: $BACKUP_FILE"; exit 1; }

    header "Restoring from: $BACKUP_FILE"
    warn "This will overwrite current configuration. Continue? [y/N]"
    read -r confirm
    [ "$confirm" = "y" ] || { echo "Aborted."; exit 0; }

    tar -xzf "$BACKUP_FILE" -C / 2>/dev/null
    nft -f /etc/nftables.conf
    systemctl restart hostapd dnsmasq AdGuardHome nftables
    ok "Restore complete. Services restarted."
    ;;

# ─── HELP ────────────────────────────────────────────────────────────────────
help|*)
    echo ""
    echo -e "${BOLD}Privacy Guardian v2.1 — Management CLI${NC}"
    echo ""
    echo "Usage: sudo pg-manage.sh <command> [args]"
    echo ""
    echo "Commands:"
    printf "  %-28s %s\n" "status"              "Show all service and stats status"
    printf "  %-28s %s\n" "logs"                "Tail live firewall + AdGuard logs"
    printf "  %-28s %s\n" "blocked"             "Show recently blocked domains and IPs"
    printf "  %-28s %s\n" "zone-logs [hours]"   "Show zone drop logs for tuning"
    printf "  %-28s %s\n" "update"              "Run all updates (trackers, packages)"
    printf "  %-28s %s\n" "reload"              "Reload nftables without rebooting"
    printf "  %-28s %s\n" "whitelist <domain>"  "Whitelist a domain in AdGuard Home"
    printf "  %-28s %s\n" "allow-device <ip> <proto> <port>"   "Add one per-device outbound allow"
    printf "  %-28s %s\n" "unallow-device <ip> <proto> <port>" "Remove one per-device outbound allow"
    printf "  %-28s %s\n" "block-device <ip>"   "Block all outbound traffic for one device"
    printf "  %-28s %s\n" "unblock-device <ip>" "Remove per-device outbound block"
    printf "  %-28s %s\n" "device-rules"        "Show active per-device firewall overrides"
    printf "  %-28s %s\n" "ban <ip>"            "Block an IP immediately"
    printf "  %-28s %s\n" "unban <ip>"          "Unblock an IP"
    printf "  %-28s %s\n" "clients"             "List connected devices"
    printf "  %-28s %s\n" "backup"              "Backup all config files"
    printf "  %-28s %s\n" "restore <file>"      "Restore from backup"
    echo ""
    ;;
esac
