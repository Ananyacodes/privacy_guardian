#!/bin/bash
# pg-manage.sh — Privacy Guardian v3.0 Management CLI (Docker)
# A single tool for all ongoing maintenance tasks in containerized environment
#
# Usage: sudo pg-manage.sh <command>
#
# Commands:
#   status          Show status of all containers
#   logs            Tail live logs from containers
#   blocked         Show recently blocked domains and IPs
#   update          Run container image updates
#   reload          Reload n ftables ruleset without rebooting
#   whitelist <domain>   Add a domain to AdGuard Home whitelist
#   ban <ip>        Manually add an IP to tracker_ips blocklist
#   unban <ip>      Remove an IP from tracker_ips blocklist
#   clients         Show connected devices and their IPs
#   backup          Backup all config files
#   restore <file>  Restore configs from backup
#   start           Start all containers
#   stop            Stop all containers
#   restart         Restart all containers
#   pull            Pull latest container images

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${BOLD}${BLUE}── $1 ──${NC}"; }
ok()     { echo -e "${GREEN}●${NC} $1"; }
fail()   { echo -e "${RED}●${NC} $1"; }
warn()   { echo -e "${YELLOW}●${NC} $1"; }
info()   { echo -e "${BLUE}[→]${NC} $1"; }

COMMAND="${1:-help}"

# Detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Check if we're in the right directory
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    fail "docker-compose.yml not found in $PROJECT_DIR"
    fail "Please run this script from the Privacy Guardian project root directory"
    exit 1
fi

case "$COMMAND" in

# ─── STATUS ──────────────────────────────────────────────────────────────────
status)
    header "Privacy Guardian v3.0 — Container Status"

    info "Checking Docker daemon..."
    docker ps -q > /dev/null 2>&1 || { fail "Docker daemon not running"; exit 1; }

    ok "Docker daemon is running"

    header "Containers"
    printf "  %-20s %-15s %-10s %s\n" "Container" "Image" "Status" "Ports"
    printf "  %-20s %-15s %-10s %s\n" "─────────" "─────" "──────" "─────"

    docker compose ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | tail -n +2 2>/dev/null || true

    header "Network"
    echo "  Pi IP (wlan0): $(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet )\S+' || echo 'not configured')"
    echo "  WAN IP (eth0): $(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet )\S+' || echo 'not configured')"

    header "DHCP Leases"
    LEASE_COUNT=$(docker compose exec -T pg-dnsmasq wc -l < /var/lib/misc/dnsmasq.leases 2>/dev/null || echo 'unknown')
    echo "  Active leases: $LEASE_COUNT"

    header "AdGuard Home"
    if docker compose exec -T pg-adguard curl -sf http://localhost:3000/login.html > /dev/null 2>&1; then
        ok "AdGuard Home is responsive"
        
        # Query stats API
        STATS=$(docker compose exec -T pg-adguard curl -sf http://localhost:3000/control/stats 2>/dev/null || echo '{}')
        if [ "$STATS" != '{}' ]; then
            DNS_QUERIES=$(echo "$STATS" | grep -oP '"num_dns_queries":\K[0-9]+' || echo 'N/A')
            BLOCKED=$(echo "$STATS" | grep -oP '"num_blocked_filtering":\K[0-9]+' || echo 'N/A')
            echo "  DNS queries: $DNS_QUERIES"
            echo "  Blocked: $BLOCKED"
        fi
    else
        warn "AdGuard Home is not responding"
    fi

    header "Firewall (nftables)"
    if docker compose exec -T pg-firewall nft list ruleset > /dev/null 2>&1; then
        ok "nftables ruleset is loaded"
        TRACKER_COUNT=$(docker compose exec -T pg-firewall nft list set inet filter tracker_ips 2>/dev/null | grep -c '\.' || echo 0)
        echo "  Tracker IPs blocked: $TRACKER_COUNT"
    else
        warn "nftables check failed"
    fi
    ;;

# ─── LOGS ────────────────────────────────────────────────────────────────────
logs)
    header "Container Logs (Ctrl+C to stop)"
    docker compose logs -f
    ;;

# ─── BLOCKED ─────────────────────────────────────────────────────────────────
blocked)
    header "Recently Blocked (last 24 hours)"
    echo ""
    echo "  ── DNS blocks (AdGuard query log) ──"
    
    docker compose exec -T pg-adguard curl -sf "http://localhost:3000/control/querylog?limit=100" 2>/dev/null \
        | grep -oP '"question":{"name":"\K[^"]+' \
        | sort | uniq -c | sort -rn \
        | head -20 \
        || warn "Could not reach AdGuard query log API"
    
    echo ""
    echo "  ── Firewall blocks ──"
    docker compose exec -T pg-firewall nft list ruleset 2>/dev/null \
        | grep -i "drop\|reject" \
        | head -10 \
        || warn "Could not read firewall rules"
    ;;

# ─── UPDATE ───────────────────────────────────────────────────────────────────
update)
    header "Running Container Updates"
    echo ""

    info "Pulling latest container images..."
    docker compose pull

    info "Reloading firewall rules..."
    docker compose exec -T pg-firewall nft -f /etc/nftables.conf || warn "Failed to reload firewall"

    ok "Updates complete"
    ;;

# ─── RELOAD ──────────────────────────────────────────────────────────────────
reload)
    header "Reloading nftables Ruleset"
    
    if docker compose exec -T pg-firewall nft --check -f /etc/nftables.conf 2>&1 | grep -q error; then
        fail "Ruleset has errors — not applied"
        exit 1
    fi

    docker compose exec -T pg-firewall nft -f /etc/nftables.conf || { fail "Failed to reload ruleset"; exit 1; }
    ok "nftables ruleset reloaded"
    ;;

# ─── WHITELIST ────────────────────────────────────────────────────────────────
whitelist)
    DOMAIN="${2:-}"
    [ -z "$DOMAIN" ] && { echo "Usage: pg-manage.sh whitelist <domain>"; exit 1; }
    
    header "Whitelisting: $DOMAIN"
    
    RESULT=$(docker compose exec -T pg-adguard curl -sf --max-time 5 \
        -X POST "http://127.0.0.1:3000/control/filtering/add_url" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"Manual whitelist\",\"url\":\"@@||${DOMAIN}^\"}" \
        2>/dev/null)
    
    if [ -n "$RESULT" ]; then
        ok "Domain '$DOMAIN' added to AdGuard whitelist"
    else
        warn "Could not add domain (verify AdGuard is running)"
    fi
    ;;

# ─── BAN ─────────────────────────────────────────────────────────────────────
ban)
    IP="${2:-}"
    [ -z "$IP" ] && { echo "Usage: pg-manage.sh ban <ip>"; exit 1; }
    
    header "Banning IP: $IP"
    
    if docker compose exec -T pg-firewall nft add element inet filter tracker_ips "{ $IP }" 2>&1; then
        ok "IP $IP added to tracker_ips blocklist (active immediately)"
        warn "This is temporary — survives until firewall reload or container restart"
    else
        fail "Failed to add $IP to blocklist"
        exit 1
    fi
    ;;

# ─── UNBAN ───────────────────────────────────────────────────────────────────
unban)
    IP="${2:-}"
    [ -z "$IP" ] && { echo "Usage: pg-manage.sh unban <ip>"; exit 1; }
    
    header "Removing IP from blocklist: $IP"
    
    if docker compose exec -T pg-firewall nft delete element inet filter tracker_ips "{ $IP }" 2>&1; then
        ok "IP $IP removed from tracker_ips"
    else
        fail "IP $IP not found in tracker_ips or error occurred"
        exit 1
    fi
    ;;

# ─── CLIENTS ─────────────────────────────────────────────────────────────────
clients)
    header "Connected Devices"
    echo ""
    printf "  %-18s %-20s %-20s %s\n" "IP Address" "MAC Address" "Hostname" "Lease Expires"
    printf "  %-18s %-20s %-20s %s\n" "──────────" "───────────" "────────" "─────────────"
    
    docker compose exec -T pg-dnsmasq cat /var/lib/misc/dnsmasq.leases 2>/dev/null | while IFS=' ' read -r expiry mac ip hostname _; do
        if [ "$expiry" = "0" ]; then
            expires="static"
        else
            expires=$(date -d "@$expiry" '+%H:%M %d/%m' 2>/dev/null || echo "unknown")
        fi
        printf "  %-18s %-20s %-20s %s\n" "$ip" "$mac" "$hostname" "$expires"
    done || warn "No DHCP leases found"
    ;;

# ─── BACKUP ──────────────────────────────────────────────────────────────────
backup)
    BACKUP_DIR="$PROJECT_DIR/backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/pg-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    header "Backing Up Configuration"
    
    tar -czf "$BACKUP_FILE" \
        "$PROJECT_DIR/nftables.conf" \
        "$PROJECT_DIR/hostapd.conf" \
        "$PROJECT_DIR/dnsmasq.conf" \
        "$PROJECT_DIR/docker-compose.yml" \
        "$PROJECT_DIR/.env" \
        "$PROJECT_DIR/Dockerfile."* \
        "$PROJECT_DIR/scripts/" \
        2>/dev/null || true

    if [ -f "$BACKUP_FILE" ]; then
        ok "Backup saved: $BACKUP_FILE"
        echo "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    else
        fail "Backup failed"
        exit 1
    fi
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

    tar -xzf "$BACKUP_FILE" -C "$PROJECT_DIR" 2>/dev/null || true
    docker compose restart
    ok "Restore complete. Containers restarted."
    ;;

# ─── START ───────────────────────────────────────────────────────────────────
start)
    header "Starting Privacy Guardian Containers"
    docker compose up -d
    ok "Containers started"
    ;;

# ─── STOP ────────────────────────────────────────────────────────────────────
stop)
    header "Stopping Privacy Guardian Containers"
    docker compose down
    ok "Containers stopped"
    ;;

# ─── RESTART ─────────────────────────────────────────────────────────────────
restart)
    header "Restarting Privacy Guardian Containers"
    docker compose restart
    ok "Containers restarted"
    ;;

# ─── PULL ────────────────────────────────────────────────────────────────────
pull)
    header "Pulling Latest Container Images"
    docker compose pull
    ok "Latest images pulled"
    info "Run 'pg-manage.sh restart' to apply updates"
    ;;

# ─── HELP ────────────────────────────────────────────────────────────────────
help|*)
    echo ""
    echo -e "${BOLD}Privacy Guardian v3.0 — Management CLI (Docker)${NC}"
    echo ""
    echo "Usage: sudo pg-manage.sh <command> [args]"
    echo ""
    echo "Container Management:"
    printf "  %-28s %s\n" "start"              "Start all containers"
    printf "  %-28s %s\n" "stop"               "Stop all containers"
    printf "  %-28s %s\n" "restart"            "Restart all containers"
    printf "  %-28s %s\n" "status"             "Show container and service status"
    printf "  %-28s %s\n" "logs"               "View all container logs"
    printf "  %-28s %s\n" "pull"               "Pull latest container images"
    echo ""
    echo "Operations:"
    printf "  %-28s %s\n" "blocked"            "Show recently blocked domains/IPs"
    printf "  %-28s %s\n" "update"             "Update container images"
    printf "  %-28s %s\n" "reload"             "Reload nftables without restart"
    printf "  %-28s %s\n" "whitelist <domain>" "Whitelist a domain"
    printf "  %-28s %s\n" "ban <ip>"           "Block an IP immediately"
    printf "  %-28s %s\n" "unban <ip>"         "Unblock an IP"
    printf "  %-28s %s\n" "clients"            "List connected devices"
    echo ""
    echo "Backup & Restore:"
    printf "  %-28s %s\n" "backup"             "Backup all configuration"
    printf "  %-28s %s\n" "restore <file>"    "Restore from backup file"
    echo ""
    ;;
esac
