# Privacy Guardian v2.1 — Zero-Leak Edition
## Complete Deployment Guide

---

## What This Is

A privacy router running on a Raspberry Pi that:
- Creates its own Wi-Fi network (hostapd)
- Assigns IPs to devices (dnsmasq DHCP)
- Filters tracking/ad/malware domains (AdGuard Home)
- Blocks all DNS bypass attempts — DoH, DoT, hardcoded DNS (nftables)
- Hides device identities behind NAT masquerade (nftables)
- Blocks known tracker IPs dynamically (nftables + FireHOL)
- Hardens SSH access and admin UI (nftables + fail2ban)
- Covers IPv6 fully — no IPv6 leak path

**Realistic false-negative rate: <10%**
(Only ultra-sophisticated hardcoded app telemetry that no Pi-level tool can stop without breaking normal internet use.)

---

## Hardware Requirements

| Component | Minimum | Recommended |
|---|---|---|
| Board | Raspberry Pi 3B | Raspberry Pi 4 (2GB+) |
| OS | Raspberry Pi OS Lite 32-bit | Raspberry Pi OS Lite 64-bit (Bookworm) |
| SD Card | 8GB Class 10 | 32GB A1/A2 rated |
| Power | 2.5A USB-C | Official Pi 4 PSU |
| Ethernet | Any USB adapter | Built-in eth0 (Pi 3/4) |

**Interfaces used:**
- `eth0` — WAN: plugs into your existing router/ISP modem
- `wlan0` — LAN: broadcasts the Privacy Guardian Wi-Fi network

---

## File Map

```
privacy-guardian/
├── install.sh                  ← Run this first (full automated setup)
├── nftables.conf               ← Firewall rules (IPv4 + IPv6)
├── hostapd.conf                ← Wi-Fi access point config
├── dnsmasq.conf                ← DHCP server config
├── dhcpcd.conf                 ← Network interface config
├── 99-privacy-guardian.conf    ← Kernel network hardening (sysctl)
├── adguard-setup.conf          ← AdGuard Home setup guide + blocklists
├── update-trackers.sh          ← Daily tracker IP blocklist updater
├── update-doh-ips.sh           ← Monthly DoH resolver IP refresher
├── disable-ipv6.sh             ← Alternative: disable IPv6 entirely
├── pg-test.sh                  ← Post-deploy diagnostics
├── pg-manage.sh                ← Ongoing management CLI
└── README.md                   ← This file
```

---

## Deployment: Step by Step

### 1. Prepare the Pi

Flash Raspberry Pi OS Lite (Bookworm) to SD card.
Enable SSH before first boot by creating an empty file named `ssh` in the boot partition.

Connect:
- Ethernet cable from Pi `eth0` → your existing router
- Power on the Pi

### 2. Transfer Files

```bash
# From your computer:
scp -r privacy-guardian/ pi@<pi-ip>:~/
ssh pi@<pi-ip>
```

### 3. Run the Installer

```bash
cd ~/privacy-guardian
chmod +x *.sh
sudo ./install.sh
```

The installer will:
- Prompt for Wi-Fi SSID password
- Prompt for your management device IP (the only device that can SSH or access AdGuard UI)
- Install all packages
- Configure all services
- Apply firewall rules
- Load initial tracker blocklist
- Run diagnostics

### 4. Complete AdGuard Home Setup

Open in browser from your management device:
```
http://192.168.4.1:3000
```

In the wizard:
1. Set admin username and strong password
2. Set DNS to listen on `0.0.0.0:53`
3. Set upstream DNS: `tls://dns.quad9.net`
4. Set bootstrap DNS: `9.9.9.9`

After wizard, add blocklists (Filters → DNS Blocklists):
- See `adguard-setup.conf` for the full recommended list

### 5. Connect and Test

Connect a device to the `PrivacyGuardian` Wi-Fi.

Run these tests:
- **DNS leak test:** https://dnsleaktest.com — should show only your ISP
- **IP leak test:** https://ipleak.net — should show only the Pi's WAN IP
- **WebRTC leak:** https://browserleaks.com/webrtc
- **AdGuard dashboard:** http://192.168.4.1:3000 — you should see queries being filtered

Run the built-in diagnostic:
```bash
sudo pg-test.sh
```

---

## Ongoing Maintenance

### Daily (automated via cron)
- `update-trackers.sh` runs at 3 AM — refreshes tracker IP blocklist

### Monthly (automated via cron)
- `update-doh-ips.sh` runs on the 1st — checks if DoH resolver IPs have changed
- Review its output in `/var/log/pg-doh-update.log` and update `nftables.conf` if new IPs appear

### Management commands

```bash
sudo pg-manage.sh status          # Check all services
sudo pg-manage.sh clients         # See connected devices
sudo pg-manage.sh blocked         # See what's being blocked
sudo pg-manage.sh whitelist example.com   # Unblock a domain
sudo pg-manage.sh ban 1.2.3.4     # Block an IP immediately
sudo pg-manage.sh reload          # Apply nftables changes without reboot
sudo pg-manage.sh backup          # Backup all configs
```

---

## Architecture Overview

```
Internet
    │
   eth0 (WAN — dynamic IP from upstream router)
    │
┌───┴────────────────────────────────────────┐
│  nftables                                  │
│  ├── ip nat prerouting: force DNS → AGH    │
│  ├── inet filter forward → privacy_chain   │
│  │   ├── Block DoH IPs on :443            │
│  │   ├── Block DoT on :853               │
│  │   ├── Block DoQ on :8853             │
│  │   └── Block tracker_ips set          │
│  └── ip/ip6 nat postrouting: masquerade   │
│                                            │
│  AdGuard Home (:53)                        │
│  ├── Blocklists (domains)                 │
│  ├── DNSSEC validation                    │
│  └── Upstream: tls://dns.quad9.net        │
│                                            │
│  dnsmasq (DHCP only)                      │
│  └── 192.168.4.10 – 192.168.4.200        │
│                                            │
│  hostapd (Wi-Fi AP)                        │
│  └── wlan0: PrivacyGuardian SSID          │
└───┬────────────────────────────────────────┘
    │
   wlan0 (LAN — 192.168.4.1/24)
    │
Connected Devices (192.168.4.10+)
```

---

## What Gets Blocked and What Doesn't

### Blocked ✓
- DNS-based tracking (ads, analytics, telemetry) — via AdGuard Home
- Hardcoded DNS (8.8.8.8, 1.1.1.1, etc.) — NAT redirect to AdGuard
- DNS-over-HTTPS bypasses — nftables blocks known resolver IPs on :443
- DNS-over-TLS bypasses — nftables blocks :853
- Known tracker IPs — dynamic FireHOL Level 1 blocklist
- Device identity from internet — NAT masquerade

### Not Blocked ✗
- VPN traffic (device-level VPN encrypts before reaching the router)
- HTTPS payload inspection (encrypted — Pi cannot see inside TLS)
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
