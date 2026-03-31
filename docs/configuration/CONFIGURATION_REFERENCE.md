# Configuration Reference

Comprehensive reference for all Privacy Guardian configuration files.

## File Locations

All configuration files are in `config/v3.0-docker/`:

```
config/v3.0-docker/
  ├── hostapd.conf                 ← Wi-Fi access point
  ├── dnsmasq.conf                 ← DHCP server
  ├── nftables.conf                ← Firewall rules
  ├── dhcpcd.conf                  ← Network interfaces
  ├── 99-privacy-guardian.conf     ← Kernel parameters
  └── adguard-setup.conf           ← DNS filtering setup
```

---

## hostapd.conf — Wi-Fi Access Point

**Purpose:** Configure the Wi-Fi network broadcast and client authentication.

**Key Settings:**

```ini
# Interface
interface=wlan0
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

# SSID & Encryption
ssid=PrivacyGuardian              # Network name
wpa=2                              # WPA2 (set to 3 for WPA3)
wpa_passphrase=YourPassword        # Pre-shared key
wpa_key_mgmt=WPA-PSK               # Key management type
wpa_pairwise=CCMP                  # Encryption: AES

# Frequency (auto-detect region)
hw_mode=g                          # 2.4GHz
channel=6                          # Channel (1, 6, or 11 for 2.4GHz)
# OR for 5GHz:
hw_mode=a
channel=36

# Security
auth_algs=1                        # Open authentication
ignore_broadcast_ssid=0            # Broadcast SSID

# Logging
logger_syslog_level=2
logger_syslog_facility=LOG_LOCAL6
```

**Modification Steps:**

1. Edit file:

   ```bash
   nano config/v3.0-docker/hostapd.conf
   ```

2. Restart service:

   ```bash
   docker compose restart hostapd
   ```

3. Verify:
   ```bash
   iw dev wlan0 info
   ```

**Common Changes:**

- Change SSID: Modify `ssid=` value
- Change password: Modify `wpa_passphrase=` value
- Enable WPA3: Set `wpa=3`
- Change channel: Modify `channel=` value

---

## dnsmasq.conf — DHCP Server

**Purpose:** Assign IP addresses to connected devices.

**Key Settings:**

```ini
# Interface
interface=wlan0
listen-address=192.168.4.1
bind-interfaces

# DHCP Configuration
dhcp-range=192.168.4.10,192.168.4.200,12h  # IP pool, lease time
dhcp-option=3,192.168.4.1         # Default gateway
dhcp-option=6,192.168.4.1         # DNS server
dhcp-option=15,privacy.local      # Domain name

# DNS
port=53                            # Listen on port 53
server=192.168.4.1                 # Dummy (DNS via AdGuard)

# Logging
log-queries
log-facility=/var/log/dnsmasq.log

# Performance
cache-size=10000
```

**Modification Steps:**

1. Edit file
2. Restart: `docker compose restart dnsmasq`
3. Verify leases: `cat /var/lib/dnsmasq/dnsmasq.leases`

**Common Changes:**

- Change IP range: Modify `dhcp-range`
- Change lease time: Modify last parameter (e.g., `24h` for 24 hours)
- Change gateway: Modify `dhcp-option=3`

---

## nftables.conf — Firewall Rules

**Purpose:** Define packet filtering, NAT, and blocking rules.

**Structure:**

```nftables
# Table definition (IPv4 filter + nat)
table inet filter {
  # Sets (IP/domain blocklists)
  set doh_resolvers { }
  set dot_resolvers { }
  set tracker_ips { }

  # Chains (rule groups)
  chain prerouting { }
  chain forward { }
  chain postrouting { }
  chain privacy_chain { }
}
```

**Key Rules:**

```nftables
# DNS redirect (prerouting)
add rule inet nat prerouting iifname "wlan0" udp dport 53 redirect to :53

# Block DoH (port 443 to resolver IPs)
add rule inet filter privacy_chain ip daddr @doh_resolvers tcp dport 443 drop

# Block DoT (port 853)
add rule inet filter privacy_chain tcp dport 853 drop

# NAT masquerade (postrouting)
add rule inet nat postrouting oifname "eth0" masquerade
```

**Modification Steps:**

1. Edit file
2. Test syntax: `sudo nft -f config/v3.0-docker/nftables.conf -c`
3. Reload: `docker compose restart firewall` or `sudo pg-manage.sh reload`
4. Verify: `sudo nft list ruleset`

**Common Changes:**

- Add IP to blocklist: `add set inet filter tracker_ips { ... }`
- Unblock port: Change `drop` to `accept` or `counter accept`
- Add exception: Add rule before blocking rule

---

## dhcpcd.conf — Network Interfaces

**Purpose:** Configure IP addresses and routing for eth0 and wlan0.

**Key Settings:**

```ini
# eth0 (WAN)
interface eth0
metric 100
# DHCP from upstream
dhcp_timeout=15

# wlan0 (LAN)
interface wlan0
metric 200
static ip_address=192.168.4.1/24
static routers=192.168.4.1
static domain_name_servers=192.168.4.1
```

**Modification Steps:**

1. Edit file (rarely needed)
2. Test: `sudo dhcpcd -T wlan0`
3. Apply: `sudo systemctl restart dhcpcd`

**Common Changes:**

- Change LAN IP: Modify `static ip_address=`
- Force static WAN IP: Add eth0 static config
- Change metric (priority): Modify `metric=` value

---

## 99-privacy-guardian.conf — Kernel Hardening

**Purpose:** Set kernel parameters for networking security.

**Location:** Loaded into `/etc/sysctl.d/` or kernel bootparams

**Key Settings:**

```ini
# IPv4 Forwarding (enable routing)
net.ipv4.ip_forward=1

# NAT
net.netfilter.nf_conntrack_max=262144
net.netfilter.nf_conntrack_tcp_timeout_established=300

# SYN Protection
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=2048

# IPv6 Privacy
net.ipv6.conf.default.use_tempaddr=2
net.ipv6.conf.all.use_tempaddr=2

# Disable IPv6 (if not wanted)
# net.ipv6.conf.all.disable_ipv6=1
```

**Modification Steps:**

1. Edit file
2. Apply: `sudo sysctl -p config/v3.0-docker/99-privacy-guardian.conf`
3. Verify: `sudo sysctl | grep 'net.ipv4.ip_forward'`

---

## adguard-setup.conf — DNS Filtering

**Purpose:** Guide for setting up AdGuard Home and blocklists.

**Contents:**

Setup wizard instructions + recommended blocklists

**Recommended Blocklists:**

```
https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://easylist-downloads.adblockplus.org/easylist.txt
https://easylist-downloads.adblockplus.org/easyprivacy.txt
https://pgl.yoyo.org/adservers/serverlist.php
```

**Add via UI:**

1. Open http://192.168.4.1:3000
2. Filters → DNS Blocklists → Add DNS Blocklist
3. Paste URL
4. Save

**Or via API:**

```bash
curl -X POST http://localhost:3000/api/adm/filtering/add_rule \
  -H "Authorization: Bearer token" \
  -d '{"rule_text":"||example.com^"}'
```

---

## .env — Environment Variables

**Purpose:** Runtime configuration (not committed to git)

**Template (.env.example):**

```bash
# Network
UPSTREAM_ROUTER_IP=192.168.1.1
WLAN_IP=192.168.4.1
WLAN_SUBNET=192.168.4.0/24
DHCP_RANGE_START=192.168.4.10
DHCP_RANGE_END=192.168.4.200

# Wi-Fi
SSID=PrivacyGuardian
WPA_PASSPHRASE=YourStrongPassword

# AdGuard
ADGUARD_IP=192.168.4.1
ADGUARD_PORT=3000
ADGUARD_DNS_PORT=53

# Management
ADMIN_IP=192.168.1.100
TIMEZONE=Asia/Kolkata

# Optional: Docker resource limits
HOSTAPD_MEMORY=256M
DNSMASQ_MEMORY=128M
FIREWALL_MEMORY=128M
```

**Usage:**

```bash
# Copy and customize
cp .env.example .env
nano .env
```

**Referenced by:**

- `docker-compose.yml` (service configuration)
- `config/v3.0-docker/*.conf` (if using env substitution)

---

## docker-compose.yml — Service Orchestration

**Purpose:** Define and configure all Docker containers.

**Key Sections:**

```yaml
version: "3.8"

services:
  hostapd:
    build:
      context: .
      dockerfile: Dockerfile.hostapd
    volumes:
      - ./config/v3.0-docker/hostapd.conf:/etc/hostapd/hostapd.conf:ro
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    environment:
      - SSID=${SSID}
      - WPA_PASS=${WPA_PASSPHRASE}

  dnsmasq:
    build:
      context: .
      dockerfile: Dockerfile.dnsmasq
    volumes:
      - ./config/v3.0-docker/dnsmasq.conf:/etc/dnsmasq.conf:ro
    ports:
      - "67:67/udp" # DHCP
      - "68:68/udp" # DHCP

  firewall:
    build:
      context: .
      dockerfile: Dockerfile.firewall
    volumes:
      - ./config/v3.0-docker/nftables.conf:/etc/nftables.conf:ro
    cap_add:
      - NET_ADMIN
    privileged: true

networks:
  privnet:
    driver: bridge
```

**Modification Steps:**

1. Edit `docker-compose.yml`
2. Test: `docker compose config`
3. Apply: `docker compose up -d`

**Common Changes:**

- Add volume mount
- Add environment variable
- Change resource limits
- Add new service

---

## Configuration Management Best Practices

### Backup Configuration

```bash
# Manual backup
tar -czf pg-config-backup.tar.gz config/v3.0-docker/ .env

# Using management CLI
sudo pg-manage.sh backup
```

### Version Control

**DO:**

- Commit: `config/v3.0-docker/*.conf` (template values)
- Commit: `.env.example` (without secrets)
- Commit: `docker-compose.yml`

**DON'T:**

- Commit: `.env` (contains secrets)
- Commit: `config/v3.0-docker/*.conf` with real values
- Store passwords in git history

### Deploy Configuration Changes

```bash
# 1. Edit file
nano config/v3.0-docker/hostapd.conf

# 2. Test (if applicable)
sudo nft -f config/v3.0-docker/nftables.conf -c

# 3. Reload/restart
docker compose restart hostapd

# 4. Verify
sudo pg-manage.sh status
```

---

## Troubleshooting Configuration

### "Configuration not applying"

Check:

1. File syntax: `cat config/v3.0-docker/file.conf | grep -v '#' | grep -v '^$'`
2. File is mounted: `docker inspect privacy-guardian-service | grep -A5 Mounts`
3. Service restarted: `docker compose restart service-name`

### "Port already in use"

Check conflicts:

```bash
sudo netstat -tlnp | grep -E ':53|:67|:3000'
```

### "Changes not persisting"

Issue: Configuration files overwritten

- Don't edit inside container: `docker exec ... edit`
- Edit host files: `nano config/v3.0-docker/file.conf`
- Restart service: `docker compose restart`

---

## See Also

- [README.md](../../README.md) — Overview
- [DEPLOYMENT_DOCKER.md](../deployment/DEPLOYMENT_DOCKER.md) — Setup guide
- [DEBUGGING.md](../troubleshooting/DEBUGGING.md) — Troubleshooting
- [HOSTAPD.md](HOSTAPD.md) — Detailed Wi-Fi configuration
- [NFTABLES.md](NFTABLES.md) — Detailed firewall rules
