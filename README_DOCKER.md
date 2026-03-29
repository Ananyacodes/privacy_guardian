# Privacy Guardian v3.0 — Docker Deployment Guide

## Overview

**Privacy Guardian** is now a fully containerized privacy router platform that runs entirely inside Docker containers. This eliminates the need to modify the host OS and provides safe, isolated operation on Raspberry Pi and other platforms.

### What Changed from v2.1?

| Aspect            | v2.1 (Host Install)                         | v3.0 (Docker)                          |
| ----------------- | ------------------------------------------- | -------------------------------------- |
| **Installation**  | Modifies host OS (`systemctl`, `/etc`, apt) | Containers + Docker Compose            |
| **Host Safety**   | Requires root changes                       | Minimal host changes                   |
| **Portability**   | Tied to OS                                  | Works anywhere (Docker installed)      |
| **Services**      | Separate systemd units                      | Containers in docker-compose.yml       |
| **Configuration** | /etc files                                  | Mounted config + volumes               |
| **Startup**       | `sudo ./install.sh`                         | `docker compose up -d`                 |
| **Management**    | `sudo pg-manage.sh`                         | `sudo pg-manage.sh` (uses docker exec) |

---

## Architecture

Privacy Guardian v3.0 uses four Docker containers working together:

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Host (Raspberry Pi)               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────┐  ┌──────────────────────────────┐ │
│  │  pg-adguard          │  │  pg-firewall (nftables)      │ │
│  │                      │  │                              │ │
│  │  DNS Filtering       │  │  IP Forwarding               │ │
│  │  Port 53 (DNS)       │  │  Firewall Rules              │ │
│  │  Port 3000 (UI)      │  │  IP Masquerade               │ │
│  │                      │  │  Tracker Blocking            │ │
│  └──────────────────────┘  └──────────────────────────────┘ │
│           ▲                           ▲                      │
│           │ DNS +                     │ Routes               │
│           │ Control                   │ Packets              │
│           │                           │                     │
│  ┌────────────────────┐  ┌────────────────────────────┐    │
│  │  pg-dnsmasq        │  │  pg-hostapd (optional)     │    │
│  │                    │  │                            │    │
│  │  DHCP Server       │  │  WiFi Access Point         │    │
│  │  IP Assignment     │  │  Broadcast Network         │    │
│  │  Network Config    │  │  Client Association        │    │
│  └────────────────────┘  └────────────────────────────┘    │
│           ▲                           ▲                     │
│           │                           │                    │
│  eth0 (WAN)                    wlan0 (LAN/WiFi)          │
│           ▼                           ▼                    │
├────────────┴──────────────────────────┴──────────────────────┤
│         Host Network Interface Bridge                        │
└─────────────────────────────────────────────────────────────┘
```

### Container Breakdown

#### 1. **pg-adguard** — DNS Filtering

- **Image**: `adguard/adguardhome:latest`
- **Purpose**: Filters DNS queries, blocks tracking/ads/malware
- **Ports**: 53 (DNS), 3000 (Admin UI)
- **Volumes**: Configuration persistence
- **Network**: Bridge (standard Docker network)

#### 2. **pg-firewall** — Network Firewall

- **Base Image**: Debian Bookworm
- **Purpose**: Applies nftables rules, IP forwarding, DoH blocking
- **Network Mode**: Host
- **Capabilities**: `NET_ADMIN`, `SYS_ADMIN`
- **Volumes**: nftables.conf (RO), logs

#### 3. **pg-dnsmasq** — DHCP Server

- **Base Image**: Debian Bookworm
- **Purpose**: Assigns IP addresses to connected devices
- **Network Mode**: Host
- **Capabilities**: `NET_ADMIN`, `NET_RAW`
- **Volumes**: dnsmasq.conf (RO), leases

#### 4. **pg-hostapd** — WiFi Access Point

- **Base Image**: Debian Bookworm
- **Purpose**: Broadcasts WiFi network (optional)
- **Network Mode**: Host
- **Capabilities**: `NET_ADMIN`, `NET_RAW`
- **Volumes**: hostapd.conf (RO), logs

---

## Prerequisites

### Hardware

- **Raspberry Pi**: 3B+, 4, 4 (8GB recommended) or compatible SBC
- **Ethernet**: Connection to upstream router
- **WiFi**: (Optional) Built-in or USB adapter
- **Power**: Official PSU (2.5A USB-C for Pi 4)

### Software

- **OS**: Raspberry Pi OS Lite (Bookworm 64-bit recommended)
- **Docker**: [Install Docker on Raspberry Pi](https://docs.docker.com/engine/install/raspberry-pi-os/)
- **Docker Compose**: [Install Docker Compose](https://docs.docker.com/compose/install/)

### System Requirements

- 500MB free disk space (for containers)
- 1GB RAM minimum (containers are lightweight)

### Network Requirements

- Ethernet cable → upstream router/modem
- WiFi module or USB adapter (for LAN broadcasting)
- Administrative device (laptop, phone) for managing AdGuard UI

---

## Installation

### 1. Flash OS to Raspberry Pi

```bash
# Use Raspberry Pi Imager: https://www.raspberrypi.com/software/
# Select:
#   OS: Raspberry Pi OS Lite (64-bit, Bookworm)
#   Storage: Your SD card

# Enable SSH before first boot:
#   - Mount boot partition
#   - Create empty file named 'ssh'
```

### 2. Boot and Connect

```bash
# Insert SD card, power on Pi
# Wait 60 seconds for first boot

# Find Pi's IP on your network
nmap -sn 192.168.1.0/24
# Or check your router's DHCP clients list

# SSH in
ssh pi@<pi-ip>
password: raspberry
```

### 3. Install Docker

```bash
# Download and run official Docker install script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add 'pi' user to docker group (optional but recommended)
sudo usermod -aG docker pi

# Verify installation
docker --version
docker compose version
```

### 4. Clone Privacy Guardian Repository

```bash
# Clone the repo
git clone https://github.com/YOUR-USERNAME/privacy_guardian.git
cd privacy_guardian

# Make scripts executable
chmod +x pg-manage.sh pg-test.sh scripts/*.sh
```

### 5. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit with your settings
nano .env
# Key settings to customize:
#   WIFI_SSID=YourNetworkName
#   WIFI_PASS=YourStrongPassword (min 8 chars)
#   MGMT_IP=192.168.4.2 (your admin device IP)
#   WIFI_COUNTRY=US (or your country)
```

### 6. Start Containers

```bash
# Build custom Dockerfiles for firewall/dnsmasq/hostapd
docker compose build

# Start all containers in background
docker compose up -d

# View startup logs
docker compose logs -f

# Wait 10-15 seconds for containers to stabilize
sleep 15
```

### 7. Verify Deployment

```bash
# Run diagnostics
sudo pg-manage.sh status

# Run full test suite
sudo pg-test.sh
```

---

## Quick Start Workflow

### First-Time Setup

```bash
cd privacy_guardian

# 1. Configure
cp .env.example .env
nano .env              # Set WiFi SSID, password, country

# 2. Build
docker compose build

# 3. Deploy
docker compose up -d

# 4. Verify
sudo pg-test.sh
```

### Accessing AdGuard Home Dashboard

1. **From Management Device** (IP specified in `MGMT_IP`):

   ```bash
   # Open in browser:
   http://192.168.4.1:3000/
   ```

2. **First-Time Setup Wizard**:
   - Admin interface: `0.0.0.0:3000`
   - DNS server: `0.0.0.0:53`
   - Create admin username and strong password
   - Add blocklists from [AdGuard Lists](https://adguardteam.github.io/)

3. **Recommended Upstream DNS** (Settings → DNS Settings):
   - `tls://dns.quad9.net` (Quad9 - privacy-focused)
   - `tls://dns.mullvad.net` (Mullvad - strict no-log)

---

## Management via CLI

All management tasks use the `pg-manage.sh` script, which now works with Docker:

```bash
# View current status
sudo pg-manage.sh status

# View live logs from all containers
sudo pg-manage.sh logs

# Show recently blocked domains (last 24h)
sudo pg-manage.sh blocked

# List connected devices
sudo pg-manage.sh clients

# Reload firewall rules (no restart)
sudo pg-manage.sh reload

# Whitelist a domain
sudo pg-manage.sh whitelist example.com

# Temporarily block an IP
sudo pg-manage.sh ban 192.168.1.100

# Unblock an IP
sudo pg-manage.sh unban 192.168.1.100

# Update container images
sudo pg-manage.sh pull

# Restart all containers
sudo pg-manage.sh restart

# Backup configuration
sudo pg-manage.sh backup

# Restore from backup
sudo pg-manage.sh restore backups/pg-backup-20261229-120000.tar.gz
```

---

## Container Management

### Docker Compose Commands

```bash
# View all containers
docker compose ps

# View logs from specific container
docker compose logs pg-adguard
docker compose logs pg-firewall
docker compose logs pg-dnsmasq

# Execute command inside container
docker compose exec pg-firewall nft list ruleset
docker compose exec pg-dnsmasq cat /var/lib/misc/dnsmasq.leases

# Stop all containers
docker compose down

# Remove all containers and volumes (WARNING: deletes AdGuard config!)
docker compose down -v
```

### Direct Docker Commands

```bash
# List running containers
docker ps

# Inspect container resources
docker inspect pg-firewall

# View container logs
docker logs pg-adguard -f

# Execute shell in container
docker exec -it pg-dnsmasq /bin/bash

# Check container IP
docker inspect pg-adguard | grep -i ipaddress

# Resource usage
docker stats
```

---

## Configuration Files

Configuration files are **read-only mounted** into containers. Edit them on the host, then reload:

### Files Used

| File                 | Container   | Purpose                               |
| -------------------- | ----------- | ------------------------------------- |
| `docker-compose.yml` | all         | Container definitions, ports, volumes |
| `nftables.conf`      | pg-firewall | Firewall rules, IP forwarding         |
| `dnsmasq.conf`       | pg-dnsmasq  | DHCP pool, lease time                 |
| `hostapd.conf`       | pg-hostapd  | WiFi settings, security               |
| `.env`               | all         | Environment variables, secrets        |

### Modifying Configuration

1. **Edit the file**:

   ```bash
   nano nftables.conf
   ```

2. **Reload container** (may vary by service):

   ```bash
   # For firewall:
   sudo pg-manage.sh reload

   # For other services:
   sudo pg-manage.sh restart
   ```

---

## Troubleshooting

### "Cannot connect to Docker daemon"

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in
logout
ssh pi@<pi-ip>

# Or use sudo
sudo docker ps
```

### "AdGuard UI not accessible"

```bash
# Check if container is running
docker compose ps pg-adguard

# Check port binding
docker compose port pg-adguard

# Test DNS from Pi
curl -I http://127.0.0.1:3000

# Test from management device (different IP)
curl -I http://192.168.4.1:3000
```

### "No internet on wlan0"

```bash
# Check interface is up
ip link show wlan0

# Check IP assignment
ip addr show wlan0

# Verify DHCP is running
docker compose exec -T pg-dnsmasq ps aux | grep dnsmasq

# Test DNS
nslookup example.com 192.168.4.1
```

### "Firewall rules not applying"

```bash
# Check nftables is loaded
docker compose exec -T pg-firewall nft list ruleset

# Reload rules
sudo pg-manage.sh reload

# Check for errors
docker compose logs pg-firewall
```

### "Containers fail to start"

```bash
# View detailed logs
docker compose logs

# Check hardware resources
free -h
df -h

# Rebuild containers
docker compose build --no-cache

# Try starting one at a time
docker compose up pg-firewall -d
docker compose up pg-dnsmasq -d
```

---

## Networking Details

### IP Assignment

- **Pi Management IP**: `192.168.4.1` (wlan0)
- **DHCP Range**: `192.168.4.10 - 192.168.4.200`
- **Gateway**: `192.168.4.1` (pointing to Pi)
- **DNS**: `192.168.4.1` (AdGuard Home)
- **Admin-only IPs**: `192.168.4.2` (SSH + AdGuard UI access only)

### Network Flow

```
Client Device
    ↓ (DHCP request)
pg-dnsmasq [DHCP] → Assigns IP from pool
    ↓ (DNS query)
pg-firewall [Firewall] → Routes to port 53
    ↓
pg-adguard [DNS] → Filters & blocks
    ↓ (Upstream)
Quad9 / Mullvad DoH → Encrypted
    ↓
pg-firewall [NAT] → Masquerade reply
    ↓
Client Device
```

### Ports Used

| Port | Protocol | Service    | Container  |
| ---- | -------- | ---------- | ---------- |
| 53   | TCP/UDP  | DNS        | pg-adguard |
| 3000 | TCP      | AdGuard UI | pg-adguard |
| 67   | UDP      | DHCP       | pg-dnsmasq |
| 22   | TCP      | SSH        | Host       |

---

## Security Considerations

### Host Prerequisites

- Run Docker as non-root user (add to `docker` group)
- Keep Docker daemon and base OS updated
- Use strong WiFi password (✓ enforced in hostapd.conf)
- Restrict SSH access (✓ nftables rules enforced)
- Enable firewall on Raspberry Pi OS

### Container Security

- ✓ Containers run with minimal privileges (except fs required NET_ADMIN)
- ✓ Configuration files mounted read-only
- ✓ No SSH inside containers (SSH on host only)
- ✓ Logs never contain passwords or secrets

### DNS Security (AdGuard)

- ✓ All upstream DNS over TLS/HTTPS (DoH)
- ✓ DoH/DoT bypass blocked by nftables
- ✓ Hardcoded DNS IPs blocked in firewall rules
- ✓ Clients cannot manually change DNS (enforced by firewall)

### WiFi Security (hostapd)

- ✓ WPA2-only (no WEP or WPA1)
- ✓ AES encryption (CCMP)
- ✓ Management frame protection enabled
- ✓ Client isolation enabled (devices can't talk directly)

---

## Updating Container Images

Privacy Guardian uses upstream images and custom Dockerfiles:

```bash
# Pull latest images
docker compose pull

# Rebuild custom containers
docker compose build --no-cache

# Restart with new images
docker compose restart

# Or in one step:
docker compose pull && docker compose build --no-cache && docker compose restart
```

---

## Backups & Restore

### Backup Configuration

```bash
sudo pg-manage.sh backup
# Creates: backups/pg-backup-YYYYMMDD-HHMMSS.tar.gz
```

**Backup includes**:

- nftables.conf
- dnsmasq.conf
- hostapd.conf
- docker-compose.yml
- .env
- Dockerfiles

**Does NOT include**:

- AdGuard Home database (stored in volumes)
- DHCP leases
- Container images (pull latest)

### Restore Configuration

```bash
sudo pg-manage.sh restore backups/pg-backup-20261229-120000.tar.gz
# Containers restart with restored config
```

### Full Backup (including AdGuard DB)

```bash
# Stop containers
docker compose down

# Backup everything
tar -czf privacy-guardian-full-$(date +%Y%m%d-%H%M%S).tar.gz \
  docker-compose.yml \
  Dockerfile* \
  *.conf \
  .env \
  scripts \
  /var/lib/docker/volumes/privacy-guardian_*

# Restart
docker compose up -d
```

---

## Uninstallation

### Clean Removal (Keeps Config)

```bash
docker compose down
# Containers stopped, volumes preserved
# Can restart anytime with: docker compose up -d
```

### Complete Removal (Deletes Everything)

```bash
docker compose down -v
# Removes containers, volumes, networks
# Config files in repo remain
# Rebuild with: docker compose up -d --build
```

### System Cleanup

```bash
# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Uninstall Docker (if desired)
sudo apt-get remove docker-ce docker-ce-cli containerd.io -y
```

---

## Performance Tuning

### For Raspberry Pi 3B/3B+

```bash
# Edit .env
RESTART_POLICY=unless-stopped

# Reduce nftables verbosity (fewer logs = less disk I/O)
# Edit nftables.conf: Comment out verbose logging rules
```

### For Raspberry Pi 4+

```bash
# Enable all services, including hostapd
# No special tuning needed
```

### Memory / CPU Monitoring

```bash
# Real-time resource usage
docker stats --no-stream

# Look for high CPU or memory usage
# If high, check logs for errors
docker compose logs --tail=50
```

---

## Advanced Topics

### Custom Upstream DNS

Edit `.env` and restart:

```bash
ADGUARD_UPSTREAM=tls://dns.example.com
docker compose restart pg-adguard
```

### Modifying Firewall Rules

Edit `nftables.conf` and reload:

```bash
nano nftables.conf
sudo pg-manage.sh reload
```

### Adding Static DHCP Leases

Edit `dnsmasq.conf`:

```bash
# Add to static leases section:
dhcp-host=aa:bb:cc:dd:ee:ff,192.168.4.50,mydevice,infinite

docker compose restart pg-dnsmasq
```

### Disabling Hostapd (WiFi)

Edit `docker-compose.yml`:

```bash
# Comment out pg-hostapd service
# Restart:
docker compose up -d
```

### Accessing Container Shell

```bash
# Open bash inside firewall container
docker compose exec pg-firewall /bin/bash

# Run commands
$ nft list ruleset
$ ip link show
$ exit
```

---

## Raspberry Pi Compatibility

| Model       | Supported         | Notes                                |
| ----------- | ----------------- | ------------------------------------ |
| Pi Zero     | ⚠️ Limited        | 512MB RAM may be tight, try it first |
| Pi 3B       | ✓ Supported       | Requires 64-bit OS (Bookworm)        |
| Pi 3B+      | ✓ Supported       | Good for home use                    |
| Pi 4 (2GB)  | ✓ Supported       | Recommended minimum for 4GB          |
| Pi 4 (4GB+) | ✓ Fully Supported | Best performance, no throttling      |
| Pi 5        | ✓ Fully Supported | Excellent performance                |
| CM4         | Custom            | Requires custom network config       |

---

## Getting Help

### Check Logs

```bash
# All containers
docker compose logs

# Specific container
docker compose logs pg-firewall -f

# With timestamps
docker compose logs --timestamps
```

### Test Basic Connectivity

```bash
# From Pi
ping 192.168.4.1          # Ping Pi itself
nslookup example.com      # Test DNS from host

# From connected device
ping 192.168.4.1          # Ping Pi gateway
nslookup example.com      # Test DNS from client
```

### Report Issues

Include:

1. Output of `docker compose ps`
2. Output of `sudo pg-test.sh`
3. Relevant container logs
4. Your `.env` (without passwords)

---

## Version History

| Version | Release  | Changes                                   |
| ------- | -------- | ----------------------------------------- |
| v3.0    | Jan 2026 | Full Docker refactor, separate containers |
| v2.1    | Nov 2025 | Last host-based version, systemd services |

---

## License

Privacy Guardian is released under the [GPL 3.0 License](LICENSE).
