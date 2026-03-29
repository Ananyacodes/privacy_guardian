# Quick Start Deployment

## 30-Second Overview

Privacy Guardian v3.0 is a containerized privacy router that runs on Docker. It provides:

- 🛡️ **DNS filtering** (AdGuard Home blocks tracking/ads/malware)
- 🚨 **Firewall** (nftables blocks DoH bypass attempts, tracker IPs)
- 📡 **WiFi** (hostapd creates private network)
- 🔄 **DHCP** (dnsmasq assigns IPs)

---

## Prerequisites

- **Hardware**: Raspberry Pi 3B/4 or similar SBC
- **OS**: Raspberry Pi OS Lite (Bookworm 64-bit recommended)
- **Internet**: Ethernet connection to upstream router
- **Software**: Docker & Docker Compose installed

### Install Docker (if not already installed)

```bash
# SSH into Pi
ssh pi@<pi-ip>

# Download and install Docker
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

---

## Deploy in 5 Minutes

### 1. Get the Code

```bash
git clone https://github.com/YOUR-USERNAME/privacy_guardian.git
cd privacy_guardian
```

### 2. Configure

```bash
# Copy example environment
cp .env.example .env

# Edit with your settings
nano .env

# Key settings:
#   WIFI_SSID=PrivacyGuardian        # Your WiFi network name
#   WIFI_PASS=Change123456            # WiFi password (min 8 chars)
#   MGMT_IP=192.168.4.2               # Your admin device IP
#   WIFI_COUNTRY=US                   # Your country code (GB, DE, IN, etc)
```

### 3. Build & Deploy

```bash
# Build Docker images
docker compose build

# Start containers in background
docker compose up -d

# Wait for stability
sleep 10
```

### 4. Verify

```bash
# Check container status
docker compose ps

# Run diagnostics
sudo pg-test.sh

# View logs (if needed)
docker compose logs
```

### 5. Access AdGuard Dashboard

From your management device, open:

```
http://192.168.4.1:3000
```

**First-time setup**:

- Admin interface: Keep `0.0.0.0:3000`
- DNS server: Keep `0.0.0.0:53`
- Create admin username and **strong password**
- Add upstream DNS: `tls://dns.quad9.net` (privacy-focused)
- Add blocklists (recommended):
  - `https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt`
  - `https://adaway.org/hosts.txt`

---

## Management Commands

All management uses the `pg-manage.sh` script:

```bash
# Show status
sudo pg-manage.sh status

# View all logs
sudo pg-manage.sh logs

# Show recently blocked domains
sudo pg-manage.sh blocked

# List connected devices
sudo pg-manage.sh clients

# Reload firewall
sudo pg-manage.sh reload

# Update container images
sudo pg-manage.sh pull

# Restart all containers
sudo pg-manage.sh restart

# Backup config
sudo pg-manage.sh backup

# Stop containers
sudo pg-manage.sh stop

# Start containers
sudo pg-manage.sh start
```

---

## Troubleshooting

### Check container health

```bash
docker compose ps
# Should show all containers with "Up" status
```

### View detailed logs

```bash
docker compose logs -f pg-adguard      # AdGuard DNS
docker compose logs -f pg-firewall     # Firewall rules
docker compose logs -f pg-dnsmasq      # DHCP server
docker compose logs -f pg-hostapd      # WiFi access point
```

### Test connectivity

```bash
# Test DNS from Pi
nslookup example.com 192.168.4.1

# Test from connected device
# Should resolve via AdGuard (most ads/trackers blocked)
```

### Fix interface configuration

```bash
# If wlan0 has no IP:
sudo ip addr add 192.168.4.1/24 dev wlan0

# Restart DHCP
docker compose restart pg-dnsmasq
```

---

## Next Steps

- 📖 See [README_DOCKER.md](README_DOCKER.md) for full documentation
- 🔄 See [MIGRATION.md](MIGRATION.md) for upgrading from v2.1
- ⚙️ Edit `.env` to customize network settings
- 🔧 Edit `nftables.conf` to customize firewall rules
- 📊 Access AdGuard UI for detailed statistics and configuration

---

## Common Customizations

### Change WiFi Password

```bash
# Edit .env
WIFI_PASS=YourNewPassword123

# Restart WiFi
docker compose restart pg-hostapd
```

### Change Management IP (for SSH/AdGuard UI access)

```bash
# Edit .env
MGMT_IP=192.168.4.50

# Reload firewall rules
sudo pg-manage.sh reload
```

### Modify DHCP Pool

```bash
# Edit dnsmasq.conf
# Change: dhcp-range=192.168.4.10,192.168.4.200,...

# Restart
docker compose restart pg-dnsmasq
```

### Update Upstream DNS

In AdGuard UI:

- Settings → DNS Settings
- Set upstream DNS resolver
- Save and restart

---

## Support Resources

- 📘 **Full Documentation**: [README_DOCKER.md](README_DOCKER.md)
- 🔄 **Migration from v2.1**: [MIGRATION.md](MIGRATION.md)
- 🐛 **Bug Reports**: GitHub Issues
- 💬 **Discussions**: GitHub Discussions

---

## Why Docker?

✅ **Safe**: No host OS modifications
✅ **Portable**: Works on any system with Docker
✅ **Easy**: Single command to deploy and manage
✅ **Reliable**: Isolated containers don't affect each other
✅ **Scalable**: Easy to add services or replicate setup

---

**Happy Privacy Guarding! 🛡️**
