# Migration Guide: v2.1 → v3.0 (Docker Edition)

## Overview

Privacy Guardian v3.0 is a complete rewrite that **moves from host-based installation to Docker containers**. This guide helps you upgrade from v2.1.

**Important**: This is a breaking change. You cannot directly upgrade in-place. Instead, you need to either:

1. Deploy to a fresh Raspberry Pi with Docker
2. Uninstall v2.1 from your Pi and install Docker

---

## What's New in v3.0

| Feature                    | v2.1                                 | v3.0                                          |
| -------------------------- | ------------------------------------ | --------------------------------------------- |
| **Installation Method**    | `sudo ./install.sh` modifies host OS | `docker compose up -d`                        |
| **Service Management**     | `systemctl` (systemd services)       | `docker compose` + `pg-manage.sh`             |
| **Configuration Location** | `/etc/` directories                  | Current directory + volumes                   |
| **Data Persistence**       | Direct filesystem                    | Docker volumes                                |
| **Host Impact**            | Modifies system files, packages      | Minimal (only /etc/nftables.conf if modified) |
| **Portability**            | OS-dependent                         | Works anywhere with Docker                    |
| **Security**               | Root privileges for install          | Minimal host modifications                    |
| **Uninstall**              | Complex (packages, systemd, cron)    | `docker compose down`                         |

---

## Quick Migration Path

### Option 1: Fresh Pi (Recommended)

```bash
# On new Raspberry Pi with Bookworm + Docker installed:

# Clone v3.0
git clone https://github.com/YOUR-USERNAME/privacy_guardian.git
cd privacy_guardian

# Configure
cp .env.example .env
nano .env

# Deploy
docker compose build
docker compose up -d

# Verify
sudo pg-test.sh

# Done! AdGuard on http://192.168.4.1:3000
```

### Option 2: Upgrade Existing Pi (v2.1 → v3.0)

#### Step 1: Backup v2.1 Configuration

```bash
# On existing Pi running v2.1
cd ~/privacy-guardian

# Backup current config
sudo pg-manage.sh backup
# Creates: /var/backups/privacy-guardian/pg-backup-*.tar.gz

# Copy to safe location
sudo cp /var/backups/privacy-guardian/pg-backup-*.tar.gz ~/
sudo chown pi:pi ~/pg-backup-*.tar.gz
```

#### Step 2: Uninstall v2.1

```bash
# Stop services
sudo systemctl stop hostapd dnsmasq AdGuardHome nftables fail2ban
sudo systemctl disable hostapd dnsmasq AdGuardHome nftables fail2ban

# Remove packages (optional, Docker is compatible with system packages)
sudo apt-get remove hostapd dnsmasq fail2ban -y
# DO NOT remove nftables — might be needed for host

# Remove old cron jobs
crontab -e
# Remove lines with update-trackers.sh, update-doh-ips.sh

# Backup old directories (optional)
sudo tar -czf ~/privacy-guardian-v2-backup.tar.gz \
  /etc/nftables.conf \
  /etc/hostapd/hostapd.conf \
  /etc/dnsmasq.conf \
  /opt/AdGuardHome/AdGuardHome.yaml
```

#### Step 3: Install Docker

```bash
# Download and run Docker install script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker pi
logout
ssh pi@<pi-ip>

# Verify
docker --version
docker compose version
```

#### Step 4: Deploy v3.0

```bash
# Clone new repo or update if you have it
cd ~/
git clone https://github.com/YOUR-USERNAME/privacy_guardian.git pg-v3
cd pg-v3

# Create .env from template
cp .env.example .env

# Option A: Manual Config
nano .env
# Set WIFI_SSID, WIFI_PASS, MGMT_IP, etc.

# Option B: Restore From v2.1 Config
# Edit .env with values from your v2.1 backup

# Build and deploy
docker compose build
docker compose up -d

# Verify health
docker compose ps
sudo pg-test.sh
```

#### Step 5: Configure AdGuard Home (First-Time Setup)

```bash
# If AdGuard data is fully fresh:

# Open http://192.168.4.1:3000 from your management device

# Step 1: Initial setup
#   Admin interface: 0.0.0.0:3000
#   DNS server: 0.0.0.0:53
#   Username: (create)
#   Password: (strong password)

# Step 2: DNS Settings
#   Upstream DNS: tls://dns.quad9.net (or your preference)
#   Bootstrap DNS: 9.9.9.9

# Step 3: Add Blocklists
#   https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
#   https://adaway.org/hosts.txt
#   ... (add from your v2.1 setup)

# Step 4: Save & restart
docker compose restart pg-adguard
```

---

## Configuration Migration

### Files That Changed

| v2.1 Location                            | v3.0 Location                                  | Notes                                                      |
| ---------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------- |
| `/etc/nftables.conf`                     | `./nftables.conf` (repo root)                  | Copy to repo, reload with `pg-manage.sh reload`            |
| `/etc/dnsmasq.conf`                      | `./dnsmasq.conf` (repo root)                   | Mounted read-only into container                           |
| `/etc/hostapd/hostapd.conf`              | `./hostapd.conf` (repo root)                   | Restart container: `docker compose restart pg-hostapd`     |
| `/etc/sysctl.d/99-privacy-guardian.conf` | Applied in firewall container                  | Settings automatically applied in `firewall-entrypoint.sh` |
| `/opt/AdGuardHome/`                      | Docker volume: `privacy-guardian_adguard-conf` | Persisted automatically, backup with `pg-manage.sh backup` |
| Cron jobs in `/etc/cron.d/`              | Removed (no auto-update)                       | Manually run: `docker compose pull` to update images       |

### Environment Variables (v2.1 → v3.0)

v2.1 used shell variables in `install.sh` prompt. v3.0 uses `.env` file:

```bash
# v2.1 (command-line prompt)
sudo WIFI_SSID="MyNetwork" WIFI_PASS="password123" MGMT_IP="192.168.4.2" ./install.sh

# v3.0 (env file)
# Edit .env:
WIFI_SSID=MyNetwork
WIFI_PASS=password123
MGMT_IP=192.168.4.2

# Then:
docker compose up -d
```

---

## Feature Comparison

### Features That Changed

| Feature             | v2.1                   | v3.0                | Migration Step                                            |
| ------------------- | ---------------------- | ------------------- | --------------------------------------------------------- |
| WiFi (hostapd)      | Systemd service        | Optional container  | Already included, no action                               |
| DHCP (dnsmasq)      | Systemd service        | Container           | Already included, configs migrated                        |
| Firewall (nftables) | Systemd service        | Always-on container | Already included, rules applied on startup                |
| AdGuard Home        | Systemd service        | Container + volume  | AdGuard uses volume, settings preserved if reusing volume |
| Auto-updates (cron) | Hour/Daily/Weekly jobs | Manual or CI/CD     | Run `docker compose pull` when you want to update         |
| Logging             | systemd journal        | `docker logs`       | Use `docker compose logs` or `sudo pg-manage.sh logs`     |
| Backups             | Cron + tar             | Manual              | Run `sudo pg-manage.sh backup` on demand                  |

### Features Removed

- ❌ **`disable-ipv6.sh`**: Not needed — nftables handles IPv6 either way
- ❌ **Automatic package updates** (unattended-upgrades): Not applicable to containers
- ❌ **fail2ban**: Can be added back as optional container if needed

### New Features in v3.0

- ✅ Full container orchestration (easy start/stop)
- ✅ Volume-based persistence (easy backups)
- ✅ Multi-stage Dockerfiles (smaller images)
- ✅ Docker Compose for easy multi-container setup
- ✅ `docker compose exec` for container commands
- ✅ Easy rollback (just pull old image)
- ✅ Works identically on Pi, Linux, even macOS for testing

---

## Troubleshooting Migration

### "AdGuard UI won't load after upgrade"

```bash
# Check if container is running
docker compose ps pg-adguard

# View logs
docker compose logs pg-adguard -f

# If data is missing, AdGuard will run first-time setup again
# (Expected after fresh v3.0 deploy without volume migration)
```

### "DHCP clients not getting IPs"

```bash
# Verify dnsmasq container is running
docker compose ps pg-dnsmasq

# Check if wlan0 has IP
ip addr show wlan0

# Set it manually if needed
sudo ip addr add 192.168.4.1/24 dev wlan0

# Restart DHCP
docker compose restart pg-dnsmasq
```

### "Firewall rules not applying"

```bash
# Check nftables is loaded
docker compose exec -T pg-firewall nft list ruleset

# View logs for errors
docker compose logs pg-firewall

# Reload rules
sudo pg-manage.sh reload
```

### "Can't reach AdGuard UI from management IP"

```bash
# Verify MGMT_IP in .env matches your device
grep MGMT_IP .env

# Check firewall allows it
docker compose exec -T pg-firewall nft list chain inet filter lan_input | grep 3000

# Test from management device
curl http://192.168.4.1:3000/
```

---

## Data Recovery

### Restored v2.1 AdGuard Database

If you want to keep your v2.1 AdGuard settings (statistics, custom filters, etc.):

1. **Find v2.1 AdGuard Data**:

   ```bash
   # Usually in /opt/AdGuardHome/
   ls -la /opt/AdGuardHome/work/
   ```

2. **Backup AdGuard Data**:

   ```bash
   sudo tar -czf ~/adguard-data-v2.tar.gz /opt/AdGuardHome/work/
   sudo chown pi:pi ~/adguard-data-v2.tar.gz
   ```

3. **Restore to v3.0 Volume**:

   ```bash
   # First, start containers to create volumes
   docker compose up -d

   # Stop AdGuard
   docker compose stop pg-adguard

   # Extract into volume
   sudo tar -xzf ~/adguard-data-v2.tar.gz \
     -C /var/lib/docker/volumes/privacy-guardian_adguard-work/_data/

   # Fix permissions
   sudo chown nobody:nogroup /var/lib/docker/volumes/privacy-guardian_adguard-work/_data/*

   # Restart
   docker compose up -d pg-adguard
   ```

---

## Rollback to v2.1 (If Needed)

```bash
# If Docker setup isn't working:

# Stop v3.0 containers
docker compose down

# Uninstall Docker packages
sudo apt-get remove docker-ce docker-ce-cli containerd.io -y

# Restore v2.1 packages
sudo apt-get install hostapd dnsmasq nftables fail2ban -y

# Restore v2.1 configuration
sudo tar -xzf ~/privacy-guardian-v2-backup.tar.gz -C /

# Start v2.1 services
sudo systemctl start hostapd dnsmasq nftables

# Restore IP forwarding settings
sudo sysctl -p /etc/sysctl.d/99-privacy-guardian.conf

#Test
sudo pg-manage.sh status  # v2.1 version
```

---

## Support

### Common Issues

**Q: Do I need to modify DHCP/WiFi settings?**

A: No! The same `.conf` files work. Just copy them into the repo root.

**Q: Will my AdGuard statistics be lost?**

A: Only if you start a fresh volume. To preserve them, migrate the `/opt/AdGuardHome/work/` directory as shown in "Data Recovery" section above.

**Q: Can I run v2.1 and v3.0 side-by-side?**

A: No, both need the same network interfaces (wlan0, eth0). Uninstall v2.1 first.

**Q: What if my Pi doesn't have Docker?**

A: Follow "Install Docker" section above, or stay on v2.1 if your kernel doesn't support Docker.

---

## Next Steps

1. **Deploy v3.0**: Follow "Option 1" or "Option 2" above
2. **Verify**: Run `sudo pg-test.sh`
3. **Port Your Config**: Copy `.conf` files from v2.1 if needed
4. **Enjoy**: Fully containerized, self-contained privacy router!

---

## Version History

| Version | Release  | Major Changes                               |
| ------- | -------- | ------------------------------------------- |
| v3.0    | Jan 2026 | **Docker refactor** — full containerization |
| v2.1    | Nov 2025 | Last host-based release                     |
| v2.0    | Sep 2025 | Added IPv6 support                          |
