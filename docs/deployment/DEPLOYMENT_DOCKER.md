# Docker Deployment Guide

Complete step-by-step guide for deploying Privacy Guardian v3.0 using Docker Compose.

## Prerequisites

- Raspberry Pi 4+ (2GB RAM minimum) or any Linux system with Docker
- Docker Engine & Docker Compose installed
- Internet connection for initial setup
- Administrative access

## Installation Steps

### 1. Install Docker & Docker Compose

```bash
# On Raspberry Pi OS
curl -sSL https://get.docker.com | sh
sudo apt-get install docker-compose

# Add user to docker group (optional, to avoid sudo)
sudo usermod -aG docker $USER
```

### 2. Clone Repository

```bash
git clone https://github.com/yourusername/privacy_guardian.git
cd privacy_guardian
```

### 3. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit with your settings
nano .env
```

**Key settings to customize:**

```bash
# Network
UPSTREAM_ROUTER_IP=192.168.1.1
WLAN_IP=192.168.4.1
WLAN_SUBNET=192.168.4.0/24
DHCP_RANGE_START=192.168.4.10
DHCP_RANGE_END=192.168.4.200

# Wi-Fi
SSID=PrivacyGuardian
WPA_PASSPHRASE=VeryStrongPassword123!

# Management
ADMIN_IP=192.168.1.100  # Your admin device
```

### 4. Start Services

```bash
# Build and start containers
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

**Expected output:**

```
CONTAINER ID   IMAGE                      STATUS          NAMES
abc12345...    privacy-guardian-hostapd   Up 2 seconds    privacy-guardian-hostapd-1
def67890...    privacy-guardian-dnsmasq   Up 2 seconds    privacy-guardian-dnsmasq-1
ghi11111...    privacy-guardian-firewall  Up 2 seconds    privacy-guardian-firewall-1
```

### 5. Configure AdGuard Home

Visit `http://192.168.4.1:3000` in your browser from your admin device.

**Setup Wizard:**

1. **Admin Password** — Set a strong password
2. **Interface Binding** — Ensure it listens on `0.0.0.0:53`
3. **Upstream DNS** — Set to `tls://dns.quad9.net` (or another Privacy-respecting resolver)
4. **Bootstrap DNS** — Set to `9.9.9.9` or `1.1.1.1`

**Add Blocklists:**

Navigate to **Settings > Filters > DNS Blocklists** and add:

```
https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://easylist-downloads.adblockplus.org/easylist.txt
https://easylist-downloads.adblockplus.org/easyprivacy.txt
https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblock
```

**See:** [adguard-setup.conf](../../config/v3.0-docker/adguard-setup.conf)

### 6. Test the Deployment

```bash
# Run diagnostics
sudo ./scripts/management/pg-test.sh

# Test DNS resolution
nslookup google.com 192.168.4.1

# Check firewall rules
sudo nft list ruleset
```

### 7. Connect Devices

Connect your devices to the `PrivacyGuardian` Wi-Fi network using the password you set in `.env`.

**Test for leaks:**

1. Visit https://dnsleaktest.com — should show your ISP DNS
2. Visit https://ipleak.net — should show only your router's WAN IP
3. Visit https://browserleaks.com/webrtc — should show only your router IP or no extension
4. Visit https://whoer.net — analyze for any leaks

---

## Ongoing Management

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f hostapd
docker compose logs -f dnsmasq
docker compose logs -f firewall
```

### Restart Services

```bash
# Restart specific service
docker compose restart hostapd

# Restart all
docker compose restart

# Full restart
docker compose down
docker compose up -d
```

### Update Configuration

Edit config files in `config/v3.0-docker/`:

```bash
# Edit hostapd settings
nano config/v3.0-docker/hostapd.conf

# Restart to apply changes
docker compose restart hostapd
```

### Stop Services

```bash
# Stop running containers
docker compose stop

# Stop and remove (data preserved)
docker compose down

# Full cleanup (removes images too)
docker compose down --rmi all
```

---

## Management CLI Commands

```bash
# System status
sudo ./scripts/management/pg-manage.sh status

# Connected clients
sudo ./scripts/management/pg-manage.sh clients

# Blocked queries
sudo ./scripts/management/pg-manage.sh blocked

# Whitelist domain
sudo ./scripts/management/pg-manage.sh whitelist example.com

# Ban IP
sudo ./scripts/management/pg-manage.sh ban 1.2.3.4

# Reload firewall
sudo ./scripts/management/pg-manage.sh reload

# Backup config
sudo ./scripts/management/pg-manage.sh backup
```

---

## Troubleshooting

### Services not starting

```bash
# Check for port conflicts
sudo netstat -tlnp | grep -E ':53|:3000|:67|:68'

# View detailed error logs
docker compose logs --tail 50 hostapd
```

### No internet access

```bash
# Check if firewall rules are applied
sudo nft list ruleset

# Test WAN connectivity
ping 8.8.8.8

# Check route table
ip route
```

### Slow DNS resolution

```bash
# Check AdGuard logs: http://192.168.4.1:3000/logs

# View query stats
dig google.com @192.168.4.1
```

**See:** [DEBUGGING.md](../troubleshooting/DEBUGGING.md) for more

---

## Advanced Configuration

### Custom Firewall Rules

Edit `config/v3.0-docker/nftables.conf` and reload:

```bash
docker compose restart firewall
```

**See:** [NFTABLES.md](../configuration/NFTABLES.md)

### Pi Resource Limits

Edit `docker-compose.yml`:

```yaml
services:
  hostapd:
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
```

### Enable IPv6

By default, IPv6 is bridged. To disable:

```bash
# In nftables.conf, uncomment IPv6 disable section
# Restart firewall
docker compose restart firewall
```

---

## Upgrading

### From v2.1 (Traditional)

See [MIGRATION.md](MIGRATION.md)

### v3.0 → v3.1+

```bash
# Pull latest
git pull

# Rebuild images
docker compose build

# Restart services
docker compose up -d
```

---

## Performance Tuning

### For Raspberry Pi 3

Limit resource usage in `docker-compose.yml`:

```yaml
services:
  hostapd:
    mem_limit: 256m
  dnsmasq:
    mem_limit: 128m
  firewall:
    mem_limit: 128m
```

### For Raspberry Pi 4+

Use all available resources:

```yaml
# Remove memory limits for better performance
```

---

## Backup & Restore

### Backup Configuration

```bash
# Manual backup
docker cp privacy-guardian-hostapd-1:/etc/hostapd ./backup/
docker cp privacy-guardian-dnsmasq-1:/etc/dnsmasq ./backup/

# Or use management CLI
sudo ./scripts/management/pg-manage.sh backup
```

### Restore from Backup

```bash
docker cp ./backup/hostapd privacy-guardian-hostapd-1:/etc/
docker compose restart hostapd
```

---

## Additional Resources

- [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) — System design
- [MANAGEMENT_CLI.md](../management/MANAGEMENT_CLI.md) — CLI reference
- [DEBUGGING.md](../troubleshooting/DEBUGGING.md) — Troubleshooting
- [Docker Docs](https://docs.docker.com/) — Docker reference
