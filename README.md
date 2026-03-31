# 🛡️ Privacy Guardian

> **Zero-Leak Privacy Router for Raspberry Pi & Docker**

Privacy Guardian is a complete privacy-focused network router that blocks tracking, ads, and malware at the DNS layer while providing complete IPv4/IPv6 protection with advanced firewall rules.

**Version:** 3.0 (Docker-based)  
**Status:** Production Ready

---

## 🚀 Quick Start

### Using Docker (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourusername/privacy_guardian.git
cd privacy_guardian

# Configure environment
cp .env.example .env
nano .env  # Edit IP addresses, SSID, password

# Start the deployment
docker compose up -d

# Check status
docker compose logs -f
```

**Time to deploy:** ~2 minutes

### Traditional Installation (v2.1)

See [DEPLOYMENT_TRADITIONAL.md](docs/deployment/DEPLOYMENT_TRADITIONAL.md)

---

## ✨ What It Does

| Feature              | Status | Details                                              |
| -------------------- | ------ | ---------------------------------------------------- |
| **DNS Filtering**    | ✅     | AdGuard Home blocks tracking/ads/malware domains     |
| **DoH/DoT Blocking** | ✅     | Blocks DNS-over-HTTPS/TLS bypass attempts            |
| **IP Blocking**      | ✅     | Dynamic FireHOL tracker IP blocklist (updated daily) |
| **NAT Masquerade**   | ✅     | Hides device identities behind router IP             |
| **IPv6 Protection**  | ✅     | Complete IPv6 privacy + leak prevention              |
| **Wi-Fi AP**         | ✅     | Hostapd-based access point (2.4GHz + 5GHz)           |
| **DHCP Server**      | ✅     | dnsmasq handles IP assignment                        |
| **Firewall**         | ✅     | nftables with advanced rules (IPv4 + IPv6)           |
| **Admin Dashboard**  | ✅     | AdGuard Home Web UI + pg-manage CLI                  |
| **Fail2Ban**         | ✅     | SSH/Admin UI brute-force protection                  |

**Expected false-negative rate: <10%**

---

## 📋 Hardware Requirements

| Component      | Minimum                     | Recommended                            |
| -------------- | --------------------------- | -------------------------------------- |
| **Board**      | Raspberry Pi 3B             | Raspberry Pi 4 (2GB+) or Pi 5          |
| **OS**         | Raspberry Pi OS Lite 32-bit | Raspberry Pi OS Lite 64-bit (Bookworm) |
| **Storage**    | 8GB SD Card Class 10        | 32GB A1/A2 rated SSD via USB3          |
| **Power**      | 2.5A USB-C                  | Official Pi 4/5 PSU                    |
| **Networking** | USB Ethernet adapter        | Built-in Gigabit eth0 (Pi 4+)          |

**Network Interfaces:**

- `eth0` — WAN: upstream router/modem (DHCP or static)
- `wlan0` — LAN: Privacy Guardian Wi-Fi network (192.168.4.0/24)

---

## 📁 Project Structure

```
privacy-guardian/
├── README.md                                 ← Start here
├── .env.example                              ← Copy to .env
├── docker-compose.yml                        ← Main deployment config
├── LICENSE                                   ← MIT License
│
├── docker/                                   ← All Docker-related files
│   ├── Dockerfile.hostapd                    ← Wi-Fi AP service
│   ├── Dockerfile.dnsmasq                    ← DHCP service
│   ├── Dockerfile.firewall                   ← Firewall (nftables) service
│   └── Dockerfile.nginx                      ← Reverse proxy (optional)
│
├── config/
│   ├── v3.0-docker/                          ← Docker-specific configs
│   │   ├── hostapd.conf                      ← Wi-Fi AP settings
│   │   ├── dnsmasq.conf                      ← DHCP configuration
│   │   ├── nftables.conf                     ← Firewall rules
│   │   ├── dhcpcd.conf                       ← Interface config
│   │   ├── 99-privacy-guardian.conf          ← Kernel hardening (sysctl)
│   │   └── adguard-setup.conf                ← AdGuard Home setup guide
│   │
│   └── v2.1-traditional/                     ← Traditional installation configs
│       ├── hostapd.conf                      ← (Same files, kept for reference)
│       ├── dnsmasq.conf
│       └── ...
│
├── scripts/
│   ├── install/
│   │   ├── install.sh                        ← Traditional OS-level installer
│   │   └── install-docker.sh                 ← Docker deployment helper
│   │
│   ├── management/
│   │   ├── pg-manage.sh                      ← Main management CLI
│   │   └── pg-test.sh                        ← Diagnostics & testing
│   │
│   └── maintenance/
│       ├── update-trackers.sh                ← Daily tracker IP list refresh
│       ├── update-doh-ips.sh                 ← Monthly DoH IP checker
│       └── disable-ipv6.sh                   ← IPv6 disabler (alternative)
│
├── ui/                                       ← Web interface & settings
│   ├── index.html                            ← Dashboard UI
│   ├── app.js                                ← Frontend logic
│   ├── styles.css                            ← UI styling
│   └── data/
│       ├── runtime.json                      ← Runtime metrics
│       └── config.js                         ← Settings
│
├── monitor/                                  ← Monitoring utilities
│   ├── device-insights.sh                    ← Per-device stats
│   └── router-control.sh                     ← Remote control commands
│
├── docs/
│   ├── deployment/
│   │   ├── DEPLOYMENT_DOCKER.md              ← Docker setup guide
│   │   ├── DEPLOYMENT_TRADITIONAL.md         ← v2.1 setup guide
│   │   └── AWS_DEPLOYMENT.md                 ← Cloud options (optional)
│   │
│   ├── architecture/
│   │   ├── ARCHITECTURE.md                   ← System design overview
│   │   ├── NETWORK_DESIGN.md                 ← Network topology
│   │   └── DATA_FLOW.md                      ← Traffic flow diagrams
│   │
│   ├── configuration/
│   │   ├── HOSTAPD.md                        ← Wi-Fi AP configuration
│   │   ├── DNSMASQ.md                        ← DHCP configuration
│   │   ├── NFTABLES.md                       ← Firewall rules
│   │   └── ADGUARD.md                        ← DNS filtering setup
│   │
│   ├── troubleshooting/
│   │   ├── FAQ.md                            ← Common questions
│   │   ├── DEBUGGING.md                      ← Debug procedures
│   │   ├── NETWORK_ISSUES.md                 ← Connection problems
│   │   └── PERFORMANCE.md                    ← Optimization tips
│   │
│   ├── management/
│   │   ├── MANAGEMENT_CLI.md                 ← pg-manage.sh reference
│   │   ├── BACKUP_RESTORE.md                 ← Data backup procedures
│   │   └── UPDATES.md                        ← Update procedures
│   │
│   └── api/
│       ├── ADGUARD_API.md                    ← AdGuard Home API
│       ├── REST_API.md                       ← pg REST endpoints (future)
│       └── WEBHOOKS.md                       ← Event webhooks (future)
│
└── .github/
    ├── workflows/
    │   ├── docker-build.yml                  ← Automated Docker builds
    │   └── ci-tests.yml                      ← CI/CD tests
    └── CONTRIBUTING.md                       ← Development guidelines
```

---

## 🚀 Deployment Options

### Option 1: Docker Compose (Recommended)

- ✅ Easy deployment & rollback
- ✅ Containerized isolation
- ✅ Built-in networking
- ✅ Simple scaling

**See:** [DEPLOYMENT_DOCKER.md](docs/deployment/DEPLOYMENT_DOCKER.md)

### Option 2: Traditional Installation

- ⚠️ Requires system-level changes
- ⚠️ No easy rollback
- ✅ Direct Pi OS integration
- ✅ Minimal overhead

**See:** [DEPLOYMENT_TRADITIONAL.md](docs/deployment/DEPLOYMENT_TRADITIONAL.md)

---

## 🔍 What Gets Blocked

### Blocked ✅

- **DNS Tracking** — AdGuard Home blocklists
- **Hardcoded DNS Bypass** — NAT redirect to local DNS
- **DNS-over-HTTPS (DoH)** — nftables blocks resolver IPs on :443
- **DNS-over-TLS (DoT)** — nftables blocks :853
- **DNS-over-QUIC (DoQ)** — nftables blocks :8853
- **Tracker IPs** — FireHOL Level 1 blocklist (updated daily)
- **IP Leaks** — NAT masquerade from 192.168.4.0/24
- **IPv6 Leaks** — IPv6 privacy + ULA routing

### NOT Blocked ❌

- **Device-level VPN** — Encrypted before reaching router
- **HTTPS Payload** — Pi cannot inspect encrypted traffic
- **Sophisticated Telemetry** — Hardcoded app analytics
- **Tor/Proxy Networks** — By design (user choice)

---

## 📊 Architecture Overview

```
                        Internet
                            │
                        (WAN IP)
                            │
              ┌─────────────┼─────────────┬──────────────┐
              │             │             │              │
          [Firewall]    [DNS Filter]  [DHCP]        [Wi-Fi AP]
          (nftables)    (AdGuard)     (dnsmasq)    (hostapd)
              │             │             │              │
              └─────────────┼─────────────┴──────────────┘
                            │
                    (192.168.4.1/24)
                            │
              ┌─────────────┼─────────────┬──────────────┐
              │             │             │              │
         [Device A]    [Device B]   [Device C]   [Management]
         192.168.4.2   192.168.4.3  192.168.4.4  192.168.4.100
```

**See:** [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md)

---

## 🛠️ Management

### Docker Commands

```bash
# View logs
docker compose logs -f

# Stop services
docker compose down

# Restart service
docker compose restart hostapd

# Shell into container
docker exec -it privacy-guardian-hostapd /bin/bash
```

### Management CLI

```bash
# Check system status
sudo pg-manage.sh status

# View connected devices
sudo pg-manage.sh clients

# See blocked domains
sudo pg-manage.sh blocked

# Whitelist a domain
sudo pg-manage.sh whitelist example.com

# Block an IP
sudo pg-manage.sh ban 1.2.3.4

# Run diagnostics
sudo pg-test.sh
```

**See:** [MANAGEMENT_CLI.md](docs/management/MANAGEMENT_CLI.md)

---

## ⚙️ Configuration

### Environment Variables (.env)

```bash
# Network Settings
UPSTREAM_ROUTER_IP=192.168.1.1          # Your existing router
WLAN_IP=192.168.4.1
WLAN_SUBNET=192.168.4.0/24
DHCP_RANGE_START=192.168.4.10
DHCP_RANGE_END=192.168.4.200

# Wi-Fi Settings
SSID=PrivacyGuardian
WPA_PASSPHRASE=YourStrongPassword

# AdGuard Settings
ADGUARD_IP=192.168.4.1
ADGUARD_PORT=3000
ADGUARD_DNS_PORT=53

# Management Settings
ADMIN_IP=192.168.1.100              # Your management device
TIMEZONE=Asia/Kolkata
```

**See:** [.env.example](.env.example)

---

## 📚 Documentation Map

| Document                                                     | Purpose                    |
| ------------------------------------------------------------ | -------------------------- |
| [DEPLOYMENT_DOCKER.md](docs/deployment/DEPLOYMENT_DOCKER.md) | Step-by-step Docker setup  |
| [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md)         | System design & components |
| [MANAGEMENT_CLI.md](docs/management/MANAGEMENT_CLI.md)       | CLI command reference      |
| [HOSTAPD.md](docs/configuration/HOSTAPD.md)                  | Wi-Fi AP configuration     |
| [NFTABLES.md](docs/configuration/NFTABLES.md)                | Firewall rules explanation |
| [FAQ.md](docs/troubleshooting/FAQ.md)                        | Common questions & answers |
| [DEBUGGING.md](docs/troubleshooting/DEBUGGING.md)            | Troubleshooting guide      |

---

## 🧪 Testing

### Pre-Deployment Tests

```bash
# Check YAML syntax
docker compose config

# Validate nftables rules
nft -f config/v3.0-docker/nftables.conf -c

# Test DNS
nslookup google.com 192.168.4.1
```

### Post-Deployment Tests

**Run the diagnostic suite:**

```bash
sudo pg-test.sh
```

**Manual leak tests:**

- DNS Leak: https://dnsleaktest.com
- IP Leak: https://ipleak.net (should show your ISP IP)
- WebRTC Leak: https://browserleaks.com/webrtc
- Full Bleed: https://whoer.net

---

## 🔐 Security Features

- ✅ **Host Isolation** — Docker containers with no host access
- ✅ **SSH Hardening** — fail2ban + key-only auth
- ✅ **Admin UI Protection** — IP whitelist + strong password
- ✅ **Firewall** — Stateful IPv4 + IPv6 filtering
- ✅ **DNSSEC** — Validation enabled on upstream DNS
- ✅ **No Special Privileges** — Services run as non-root (where possible)
- ✅ **Audit Logging** — All blocked domains logged to AdGuard

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](.github/CONTRIBUTING.md)

**Ways to help:**

- Bug reports & fixes
- Configuration examples
- Documentation improvements
- Docker optimization
- Testing on new Pi hardware

---

## 📝 License

MIT License — See [LICENSE](LICENSE)

---

## ❓ Support

1. **Check the FAQ** → [FAQ.md](docs/troubleshooting/FAQ.md)
2. **Enable debug mode** → See [DEBUGGING.md](docs/troubleshooting/DEBUGGING.md)
3. **Review logs** → `docker compose logs -f`
4. **Open an issue** → GitHub Issues

---

## 🗺️ Roadmap

- [ ] v3.1 — Kubernetes support
- [ ] v3.2 — REST API for remote management
- [ ] v3.3 — Mobile app (iOS/Android)
- [ ] v3.4 — Prometheus metrics export
- [ ] v3.5 — Multi-Pi clustering

---

**Last Updated:** March 2026  
**Maintainer:** [Your Name/Organization]

- Ultra-sophisticated telemetry using CDN IPs shared with legitimate traffic
- Tracking via browser fingerprinting (network-level cannot stop this)
- Apps with hardcoded IP telemetry not on any blocklist

---

## Troubleshooting

### "Can't connect to Wi-Fi"

```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
# Common: wrong country_code in hostapd.conf, or wlan0 is in use
rfkill list     # Check if Wi-Fi is blocked
rfkill unblock wifi
```

### "Connected but no internet"

```bash
sudo systemctl status nftables
sudo nft list ruleset | grep forward    # Check forward chain policy
sudo systemctl status AdGuardHome
# Verify IP forwarding:
sysctl net.ipv4.ip_forward              # Should be 1
```

### "DNS not resolving"

```bash
# Test AdGuard Home directly:
dig @192.168.4.1 example.com
sudo systemctl status AdGuardHome
sudo ss -lnup | grep :53    # Check port 53 is listening
```

### "A specific site is broken"

```bash
# Check if it's being blocked by AdGuard:
sudo pg-manage.sh blocked
# Whitelist the domain:
sudo pg-manage.sh whitelist example.com
```

### "SSH is blocked / can't access AdGuard UI"

```bash
# Check your management IP is correct in nftables.conf
sudo nft list chain inet filter lan_input | grep MGMT
# Temporarily allow from any LAN IP (emergency only):
sudo nft insert rule inet filter lan_input tcp dport 22 accept
# Then fix MGMT_IP and reload properly
```

### "nftables rules not persisting after reboot"

```bash
sudo systemctl enable nftables
sudo systemctl status nftables
# Verify the service loads /etc/nftables.conf on boot
```

---

## Security Notes

- **Change the default Wi-Fi password** immediately — `CHANGE_THIS_PASSWORD_NOW` is not a real password
- **MGMT_IP restriction** — only your management device can SSH or access AdGuard UI. If you change devices, update `MGMT_IP` in `/etc/nftables.conf` and run `sudo pg-manage.sh reload`
- **SD card wear** — logging is configured conservatively; avoid enabling verbose logging in production
- **AdGuard password** — set a strong password in the initial wizard; the UI has no network-level auth other than the nftables MGMT_IP restriction
- **Upstream DNS privacy** — Quad9 and Mullvad both have strong no-logging policies as of 2026; your ISP cannot see your DNS queries but your upstream resolver can

---

## Web UI Prototype

A basic frontend is now available in `docs/ui/` with:

- Wi-Fi setup steps (generic WPA flow)
- OTA firmware update action
- Settings UI for WPA2/WPA3 and firewall mode selection
- Admin credential change command generator
- Dashboard cards for internet status, network map, and security status
- Device management table with category-aware detection and usage tracking hints
- Restart and toggle controls for firewall, Wi-Fi AP, and DNS filter

### Files

- `docs/ui/index.html` — main dashboard page
- `docs/ui/styles.css` — styling and responsive layout
- `docs/ui/app.js` — rendering and command-generation logic
- `docs/ui/data/runtime.json` — runtime data consumed by the UI
- `monitor/device-insights.sh` — generates runtime JSON with device categories
- `monitor/router-control.sh` — restart/toggle/OTA/admin action script

### Run locally

```bash
# 1) Generate latest data snapshot for dashboard
sudo chmod +x monitor/*.sh
sudo ./monitor/device-insights.sh ./docs/ui/data/runtime.json

# 2) Open the UI directly in a browser
# (or serve docs/ui with any static file server)
xdg-open docs/ui/index.html
```

### Device Management Detection Rules

- **IoT**: hostnames like `tv`, `fridge`, `camera`, `thermostat`, `plug`, `bulb`
- **Personal**: hostnames like `laptop`, `phone`, `iphone`, `android`, `ipad`, `macbook`
- **Public**: any SSH-reachable device (`:22`) and hostnames like `server`, `nas`, `desktop`, `workstation`, `pc`
- **Unknown**: devices that do not match current heuristics

Current usage tracking is estimated from active conntrack flows and byte counters when available (`/proc/net/nf_conntrack`).
