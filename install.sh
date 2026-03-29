#!/bin/bash
# install.sh — Privacy Guardian v2.1 Full Installer (DEPRECATED)
#
# ⚠️  DEPRECATED: This is the old host-based installer for v2.1
#     Privacy Guardian v3.0+ uses Docker for safe containerized deployment
#
# ✓ Recommended: Use Privacy Guardian v3.0 (Docker)
#   See: README_DOCKER.md or run: docker compose up -d
#
# ⚠️  This script modifies your host OS system files and cannot be easily uninstalled
#
# If you choose to use v2.1:
# Run as root on a fresh Raspberry Pi OS Lite (Bookworm 64-bit recommended)
# Installs and configures: hostapd, dnsmasq, AdGuard Home, nftables, sysctl hardening
#
# Usage:
#   chmod +x install.sh
#   sudo ./install.sh
#
# Time to complete: ~5 minutes (depending on internet speed)
#
# For migration from v2.1 to v3.0, see: MIGRATION.md

set -euo pipefail

# ─── Colour output ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
info()    { echo -e "${BLUE}[→]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
die()     { echo -e "${RED}[✗] FATAL: $1${NC}" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}══ $1 ══${NC}"; }

# ─── Preflight ────────────────────────────────────────────────────────────────
section "Preflight Checks"

[ "$(id -u)" -eq 0 ] || die "Must be run as root. Use: sudo ./install.sh"

# Detect interfaces
WAN_IF="eth0"
LAN_IF="wlan0"

ip link show "$WAN_IF" &>/dev/null || die "WAN interface $WAN_IF not found. Plug in ethernet."
ip link show "$LAN_IF" &>/dev/null || die "LAN interface $LAN_IF not found. Check Wi-Fi hardware."

log "Interfaces OK: WAN=$WAN_IF, LAN=$LAN_IF"

# Check internet connectivity on WAN
if ! curl -sf --max-time 5 https://example.com &>/dev/null; then
    die "No internet on $WAN_IF. Connect ethernet to your upstream router first."
fi
log "Internet connectivity confirmed"

# ─── Configuration Variables ─────────────────────────────────────────────────
section "Configuration"

WIFI_SSID="${WIFI_SSID:-PrivacyGuardian}"
WIFI_PASS="${WIFI_PASS:-}"
MGMT_IP="${MGMT_IP:-}"
PI_IP="192.168.4.1"
LAN_NET="192.168.4.0/24"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prompt for Wi-Fi password if not set via environment
if [ -z "$WIFI_PASS" ]; then
    echo ""
    read -rsp "  Enter Wi-Fi password for '$WIFI_SSID' (min 8 chars): " WIFI_PASS
    echo ""
    [ ${#WIFI_PASS} -ge 8 ] || die "Password must be at least 8 characters"
fi

# Prompt for management IP if not set
if [ -z "$MGMT_IP" ]; then
    echo ""
    read -rp "  Enter management device IP (will have SSH + AdGuard UI access): " MGMT_IP
    echo ""
    [[ "$MGMT_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || die "Invalid IP: $MGMT_IP"
fi

log "SSID: $WIFI_SSID"
log "Management IP: $MGMT_IP"

# ─── System Update ───────────────────────────────────────────────────────────
section "System Update"

info "Updating package lists..."
apt-get update -qq

info "Upgrading installed packages..."
apt-get upgrade -y -qq

# ─── Install Dependencies ────────────────────────────────────────────────────
section "Installing Packages"

PACKAGES=(
    hostapd          # Wi-Fi access point
    dnsmasq          # DHCP server
    nftables         # Firewall
    curl             # Downloads + health checks
    wget             # Alternative downloader
    dnsutils         # dig command (for update-doh-ips.sh)
    iptables         # Legacy — some tools still reference it
    netfilter-persistent  # Persist nftables rules across reboots
    ulogd2           # Optional: structured firewall logging
    logrotate        # Log rotation to protect SD card
    fail2ban         # SSH brute force protection (extra layer)
    unattended-upgrades  # Automatic security updates
)

info "Installing: ${PACKAGES[*]}"
apt-get install -y -qq "${PACKAGES[@]}"
log "All packages installed"

# ─── Disable conflicting services ────────────────────────────────────────────
section "Disabling Conflicting Services"

# Stop NetworkManager interfering with our static config
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    systemctl disable --now NetworkManager
    warn "NetworkManager disabled — using dhcpcd instead"
fi

# Unblock Wi-Fi (some Pi OS builds have rfkill blocking wlan0)
if command -v rfkill &>/dev/null; then
    rfkill unblock wifi || true
    log "Wi-Fi unblocked via rfkill"
fi

# ─── Configure Static IP on wlan0 ────────────────────────────────────────────
section "Network Interface Configuration"

info "Configuring static IP $PI_IP on $LAN_IF..."

# Install dhcpcd.conf
if [ -f "$SCRIPT_DIR/dhcpcd.conf" ]; then
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak
    cp "$SCRIPT_DIR/dhcpcd.conf" /etc/dhcpcd.conf
    log "dhcpcd.conf installed"
else
    # Fallback: append to existing dhcpcd.conf
    cat >> /etc/dhcpcd.conf << EOF

# Privacy Guardian — added by install.sh
interface wlan0
    static ip_address=192.168.4.1/24
    nogateway
    nohook wpa_supplicant
EOF
    log "Static IP appended to existing dhcpcd.conf"
fi

systemctl restart dhcpcd
log "dhcpcd restarted"

# ─── Configure hostapd ───────────────────────────────────────────────────────
section "Wi-Fi Access Point (hostapd)"

info "Configuring hostapd..."

if [ -f "$SCRIPT_DIR/hostapd.conf" ]; then
    cp "$SCRIPT_DIR/hostapd.conf" /etc/hostapd/hostapd.conf
else
    cat > /etc/hostapd/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=$WIFI_SSID
wpa_passphrase=$WIFI_PASS
hw_mode=g
channel=6
ieee80211n=1
ieee80211d=1
country_code=US
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_pairwise=CCMP
ieee80211w=1
ap_isolate=1
ignore_broadcast_ssid=0
max_num_sta=20
EOF
fi

# Apply SSID and password from user input (overrides placeholders in conf file)
sed -i "s/^ssid=.*/ssid=$WIFI_SSID/" /etc/hostapd/hostapd.conf
sed -i "s/^wpa_passphrase=.*/wpa_passphrase=$WIFI_PASS/" /etc/hostapd/hostapd.conf

# Point hostapd to config file
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

# Unmask and enable (hostapd is masked by default on Raspberry Pi OS)
systemctl unmask hostapd
systemctl enable hostapd
systemctl restart hostapd && log "hostapd started" || warn "hostapd failed to start — check: journalctl -u hostapd"

# ─── Configure dnsmasq ───────────────────────────────────────────────────────
section "DHCP Server (dnsmasq)"

info "Configuring dnsmasq (DHCP only)..."

cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null || true

if [ -f "$SCRIPT_DIR/dnsmasq.conf" ]; then
    cp "$SCRIPT_DIR/dnsmasq.conf" /etc/dnsmasq.conf
else
    cat > /etc/dnsmasq.conf << EOF
port=0
interface=wlan0
bind-interfaces
except-interface=eth0
dhcp-range=192.168.4.10,192.168.4.200,255.255.255.0,12h
dhcp-option=option:router,192.168.4.1
dhcp-option=option:dns-server,192.168.4.1
dhcp-authoritative
log-dhcp
bogus-priv
no-resolv
EOF
fi

systemctl enable dnsmasq
systemctl restart dnsmasq && log "dnsmasq started" || warn "dnsmasq failed — check: journalctl -u dnsmasq"

# ─── Kernel Parameters ───────────────────────────────────────────────────────
section "Kernel Network Hardening (sysctl)"

if [ -f "$SCRIPT_DIR/99-privacy-guardian.conf" ]; then
    cp "$SCRIPT_DIR/99-privacy-guardian.conf" /etc/sysctl.d/99-privacy-guardian.conf
else
    cat > /etc/sysctl.d/99-privacy-guardian.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_tw_reuse = 1
net.netfilter.nf_conntrack_max = 65536
net.ipv6.conf.eth0.accept_ra = 0
net.ipv6.conf.wlan0.accept_ra = 0
EOF
fi

sysctl --system -q
log "sysctl parameters applied"

# ─── Firewall (nftables) ─────────────────────────────────────────────────────
section "Firewall (nftables)"

info "Applying nftables ruleset..."

# Substitute MGMT_IP into nftables.conf
if [ -f "$SCRIPT_DIR/nftables.conf" ]; then
    sed "s/192\.168\.4\.2/$MGMT_IP/g" "$SCRIPT_DIR/nftables.conf" > /etc/nftables.conf
else
    die "nftables.conf not found in $SCRIPT_DIR. Cannot configure firewall."
fi

# Validate before applying
if ! nft --check -f /etc/nftables.conf; then
    die "nftables.conf validation failed. Check syntax."
fi

nft -f /etc/nftables.conf
systemctl enable nftables
log "nftables rules loaded and enabled"

# ─── Install AdGuard Home ─────────────────────────────────────────────────────
section "AdGuard Home (DNS Filtering)"

if systemctl is-active --quiet AdGuardHome 2>/dev/null; then
    warn "AdGuard Home already installed and running — skipping install"
else
    info "Downloading and installing AdGuard Home..."
    curl -s -S -L \
        https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh \
        | sh -s -- -s

    systemctl enable --now AdGuardHome
    log "AdGuard Home installed and started"
fi

# ─── Install Update Scripts ───────────────────────────────────────────────────
section "Installing Update Scripts"

SCRIPTS=(update-trackers.sh update-doh-ips.sh pg-test.sh)
for script in "${SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        cp "$SCRIPT_DIR/$script" /usr/local/bin/"$script"
        chmod +x /usr/local/bin/"$script"
        log "Installed /usr/local/bin/$script"
    else
        warn "$script not found in $SCRIPT_DIR — skipping"
    fi
done

# ─── Set Up Cron Jobs ────────────────────────────────────────────────────────
section "Scheduling Automated Updates"

CRON_FILE="/etc/cron.d/privacy-guardian"
cat > "$CRON_FILE" << EOF
# Privacy Guardian v2.1 — automated maintenance tasks
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Update tracker IP blocklist daily at 3:00 AM
0 3 * * * root /usr/local/bin/update-trackers.sh >> /var/log/pg-tracker-update.log 2>&1

# Refresh DoH resolver IP list monthly (outputs to /tmp for manual review)
0 4 1 * * root /usr/local/bin/update-doh-ips.sh >> /var/log/pg-doh-update.log 2>&1

# Run diagnostics weekly and log results
0 5 * * 0 root /usr/local/bin/pg-test.sh >> /var/log/pg-diagnostics.log 2>&1
EOF

log "Cron jobs installed at $CRON_FILE"

# ─── Configure Log Rotation ───────────────────────────────────────────────────
section "Log Rotation (SD Card Protection)"

cat > /etc/logrotate.d/privacy-guardian << 'EOF'
/var/log/pg-*.log {
    weekly
    rotate 2
    compress
    missingok
    notifempty
    size 5M
}

/var/log/dnsmasq.log {
    weekly
    rotate 2
    compress
    missingok
    notifempty
    size 10M
    postrotate
        systemctl reload dnsmasq > /dev/null 2>&1 || true
    endscript
}
EOF

log "Log rotation configured"

# ─── Configure fail2ban for SSH ───────────────────────────────────────────────
section "fail2ban (SSH Brute Force Protection)"

cat > /etc/fail2ban/jail.d/privacy-guardian.conf << EOF
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime  = 3600
ignoreip = 127.0.0.1/8 $MGMT_IP
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban configured (SSH: 3 retries, 1h ban)"

# ─── Enable Unattended Security Updates ──────────────────────────────────────
section "Automatic Security Updates"

cat > /etc/apt/apt.conf.d/50privacy-guardian << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

log "Unattended security upgrades enabled"

# ─── Initial Tracker Update ───────────────────────────────────────────────────
section "Initial Tracker IP Population"

info "Running initial tracker update (may take 30 seconds)..."
/usr/local/bin/update-trackers.sh && log "Initial tracker IPs loaded" || warn "Initial tracker update failed — will retry via cron at 3AM"

# ─── Final Summary ────────────────────────────────────────────────────────────
section "Installation Complete"

echo ""
echo -e "${BOLD}Privacy Guardian v2.1 is installed.${NC}"
echo ""
echo -e "  Wi-Fi SSID:       ${GREEN}$WIFI_SSID${NC}"
echo -e "  Pi IP:            ${GREEN}$PI_IP${NC}"
echo -e "  Management IP:    ${GREEN}$MGMT_IP${NC} (SSH + AdGuard UI access only)"
echo -e "  AdGuard Home UI:  ${GREEN}http://$PI_IP:3000${NC} (from $MGMT_IP only)"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "  1. Connect to Wi-Fi: '$WIFI_SSID'"
echo "  2. Open AdGuard Home: http://$PI_IP:3000"
echo "     → Complete the setup wizard"
echo "     → Add blocklists (see adguard-setup.conf)"
echo "     → Set upstream DNS to tls://dns.quad9.net"
echo "  3. Run diagnostics: sudo pg-test.sh"
echo "  4. Test DNS leak: https://dnsleaktest.com"
echo "  5. Test IP leak: https://ipleak.net"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "  - Change the Wi-Fi password in /etc/hostapd/hostapd.conf if not done via wizard"
echo "  - Set country_code in /etc/hostapd/hostapd.conf to your country (currently: US)"
echo "  - Review /etc/nftables.conf MGMT_IP ($MGMT_IP) is correct"
echo ""

# Run diagnostics
info "Running post-install diagnostics..."
/usr/local/bin/pg-test.sh || true

echo ""
log "Installation finished. Connect a device and test!"
