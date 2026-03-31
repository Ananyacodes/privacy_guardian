# Management CLI Reference

Complete command reference for `pg-manage.sh` — the Privacy Guardian management utility.

## Overview

```bash
sudo ./scripts/management/pg-manage.sh [COMMAND] [OPTIONS]
```

All commands require `sudo` to access system-level information and configuration files.

---

## Commands

### status

Check the status of all Privacy Guardian services.

```bash
sudo pg-manage.sh status
```

**Output:**

```
🛡️  Privacy Guardian Status

Services:
  ✅ hostapd (Wi-Fi AP)      - Running
  ✅ dnsmasq (DHCP)          - Running
  ✅ firewall (nftables)     - Running
  ✅ AdGuard Home (DNS)      - Running

Network:
  eth0 (WAN): 203.0.113.42
  wlan0 (LAN): 192.168.4.1/24

Wi-Fi:
  SSID: PrivacyGuardian
  Clients: 3 connected

Firewall:
  Rules loaded: 127
  IPv6: Enabled (ULA)
  IPv4 masquerade: Active
```

---

### clients

List all devices connected to the Wi-Fi network.

```bash
sudo pg-manage.sh clients
```

**Output:**

```
Connected Clients:

MAC Address          IP Address       Hostname          Signal   Status
f8:32:e4:a1:b2:c3  192.168.4.10    iPhone-Ayman       -35dBm   Associated
a4:5e:60:d1:e2:f3  192.168.4.11    Samsung-Galaxy     -42dBm   Associated
2c:41:38:g4:h5:i6  192.168.4.12    MacBook-Pro        -28dBm   Associated
```

---

### blocked

Show recently blocked queries — both DNS-based and IP-based blocks.

```bash
sudo pg-manage.sh blocked                # Last 50 blocks
sudo pg-manage.sh blocked 100            # Last 100 blocks

# Filter by type
sudo pg-manage.sh blocked --filter ads
sudo pg-manage.sh blocked --filter trackers
```

**Output:**

```
Blocked Queries (Last 50):

Timestamp            Device IP        Domain                           Reason
2026-03-31 14:23:11  192.168.4.10    analytics.google.com             AdList: Google Analytics
2026-03-31 14:22:45  192.168.4.11    doubleclick.net                  AdList: Google DoubleClick
2026-03-31 14:22:12  192.168.4.12    cdn.scorecardresearch.com        AdList: Scorecard Research
...

Summary:
  Total blocked: 1,247
  Ads: 842
  Trackers: 312
  Malware: 93
```

---

### whitelist

Whitelist a blocked domain.

```bash
sudo pg-manage.sh whitelist example.com

# Multiple domains
sudo pg-manage.sh whitelist example.com another-site.io
```

**Output:**

```
✅ Added example.com to whitelist
   Reload AdGuard to apply: pg-manage.sh reload
```

**What it does:**

- Adds domain to AdGuard Home's whitelist
- Queries for this domain will no longer be blocked
- Takes effect immediately (no reload needed)

---

### ban

Block an IP address immediately.

```bash
sudo pg-manage.sh ban 1.2.3.4

# Multiple IPs
sudo pg-manage.sh ban 1.2.3.4 5.6.7.8
```

**Output:**

```
✅ Added 1.2.3.4 to firewall blocklist
   Rules reloaded
```

**What it does:**

- Adds IP to nftables blocklist set
- Blocks all connections to/from this IP
- Takes effect immediately

---

### reload

Reload firewall rules and services without restarting.

```bash
sudo pg-manage.sh reload
```

**Output:**

```
⟳ Reloading services...
  ✅ Firewall rules reloaded
  ✅ DHCP leases refreshed
  ✅ DNS cache cleared

All services active and responsive.
```

**Use cases:**

- Applied manual edits to nftables.conf
- Updated firewall rules
- Need to apply changes without full restart

---

### backup

Create a backup of all configuration files.

```bash
sudo pg-manage.sh backup                  # Backup to default location
sudo pg-manage.sh backup /mnt/backup      # Backup to specific path
```

**Output:**

```
📦 Creating backup...
   hostapd.conf         ✅
   dnsmasq.conf         ✅
   nftables.conf        ✅
   99-privacy-guardian.conf ✅

Backup created: /var/backups/pg-2026-03-31-142311.tar.gz
Size: 2.4 MB
```

**What gets backed up:**

- All config files
- Firewall rules
- DHCP leases
- AdGuard Home settings (if included)
- SSL certificates (if any)

---

### restore

Restore configuration from a backup.

```bash
sudo pg-manage.sh restore /var/backups/pg-2026-03-31-142311.tar.gz
```

**Output:**

```
📥 Restoring from backup...
   Verifying backup integrity... ✅
   Stopping services...         ✅
   Extracting files...          ✅
   Starting services...         ✅

Restore complete. Please verify configuration.
```

---

### stats

Show real-time statistics and metrics.

```bash
sudo pg-manage.sh stats                 # Overall stats
sudo pg-manage.sh stats --live          # Live updates
```

**Output:**

```
Statistics:

Network Traffic:
  Upload: 245 KB/s
  Download: 1.2 MB/s
  Total: 1.4 MB/s

DNS Queries (realtime):
  Queries: 84/min
  Blocked: 32/min (38%)
  Response time: 45ms avg

Clients:
  Connected: 3
  Idle: 0
  Total bandwidth: 1.4 MB/s

Services CPU/Memory:
  hostapd:  2% / 64 MB
  dnsmasq:  1% / 28 MB
  firewall: 3% / 52 MB
  AdGuard:  8% / 156 MB
```

---

### logs

View system logs with filtering.

```bash
sudo pg-manage.sh logs hostapd          # Wi-Fi AP logs
sudo pg-manage.sh logs dnsmasq          # DHCP logs
sudo pg-manage.sh logs firewall         # Firewall logs

sudo pg-manage.sh logs all --tail 100   # Last 100 lines, all services
```

**Output:**

```
[hostapd]
Mar 31 14:23:11 Privacy-Guardian hostapd: f8:32:e4:a1:b2:c3: STA-CONNECT-FAILED
Mar 31 14:22:45 Privacy-Guardian hostapd: a4:5e:60:d1:e2:f3: STA-AUTH
...

[dnsmasq]
Mar 31 14:23:08 Privacy-Guardian dnsmasq[641]: 192.168.4.10/45812 query[A] ...
...
```

---

### test

Run diagnostic tests (alias for `pg-test.sh`).

```bash
sudo pg-manage.sh test
```

Runs full system diagnostics:

- Network connectivity
- DNS resolution
- Firewall rules
- Service health
- IPv6 configuration

**Output:**

```
🔍 Running Diagnostics...

✅ Network
   WAN connectivity: OK
   LAN connectivity: OK
   Gateway reachable: OK

✅ DNS
   Local resolution: OK (192.168.4.1)
   Upstream: OK (9.9.9.9)
   DNSSEC: OK

✅ Services
   hostapd: Running ✅
   dnsmasq: Running ✅
   firewall: Running ✅
   AdGuard: Running ✅

All systems operational!
```

---

### config

Display current configuration.

```bash
sudo pg-manage.sh config                # Show all config
sudo pg-manage.sh config wlan            # Show Wi-Fi config
sudo pg-manage.sh config firewall        # Show firewall config
```

**Output:**

```
Active Configuration:

Network:
  WAN interface: eth0
  LAN interface: wlan0
  WLAN IP: 192.168.4.1/24

Wi-Fi:
  SSID: PrivacyGuardian
  Channel: Auto
  Mode: 802.11ac
  Security: WPA2-PSK

Firewall:
  IPv4 masquerade: Enabled
  IPv6: Enabled (ULA)
  DoH blocking: Enabled
  DoT blocking: Enabled
```

---

### update

Manually trigger updates (normally automatic via cron).

```bash
sudo pg-manage.sh update trackers        # Update tracker IP blocklist
sudo pg-manage.sh update doh             # Check DoH resolver IPs
```

**Output:**

```
Updating tracker IP blocklist...

Downloaded: firehol_level1.txt (5,247 entries)
Previous: 5,031 entries

Changes:
  New IPs: 216
  Removed: 0

✅ Tracker list updated
   Firewall rules reloaded
```

---

### help

Show command help.

```bash
sudo pg-manage.sh help
sudo pg-manage.sh help [COMMAND]         # Help for specific command
```

**Output:**

```
Privacy Guardian Management CLI

Usage: pg-manage.sh [COMMAND] [OPTIONS]

Commands:
  status              Show service status
  clients             List connected clients
  blocked             Show blocked queries
  whitelist           Whitelist a domain
  ban                 Block an IP address
  reload              Reload services
  backup              Backup configuration
  restore             Restore from backup
  stats               Show statistics
  logs                View system logs
  test                Run diagnostics
  config              Show active config
  update              Update blocklists
  help                Show this help

Use 'pg-manage.sh help [COMMAND]' for more details.
```

---

## Usage Examples

### Monitor in Real-Time

```bash
# One terminal
watch -n 1 'sudo pg-manage.sh status'

# Another terminal
sudo pg-manage.sh logs all --live
```

### Troubleshoot Blocked Domain

```bash
# Find the domain being blocked
sudo pg-manage.sh blocked | grep example.com

# Check which list blocked it
curl -s http://192.168.4.1:3000/logs | grep example.com

# Whitelist it
sudo pg-manage.sh whitelist example.com
```

### Block a Malicious IP

```bash
# Identify attacker IP
sudo pg-manage.sh logs firewall | grep "DROP"

# Block it
sudo pg-manage.sh ban 192.0.2.42

# Verify
sudo pg-manage.sh stats
```

### Regular Maintenance

```bash
# Weekly backup
sudo pg-manage.sh backup /mnt/external-drive/

# Monthly full diagnostics
sudo pg-manage.sh test

# Check for updates
sudo pg-manage.sh update trackers
sudo pg-manage.sh update doh
```

---

## Exit Codes

- `0` — Success
- `1` — General error
- `2` — Command not found
- `3` — Permission denied (not running as sudo)
- `4` — Service unavailable

---

## Configuration Files

The management CLI reads from:

- `.env` — Environment variables
- `config/v3.0-docker/*.conf` — Configuration files
- `/var/log/pg-*.log` — Log files

---

## See Also

- [README.md](../../README.md) — Main overview
- [DEPLOYMENT_DOCKER.md](../deployment/DEPLOYMENT_DOCKER.md) — Docker setup
- [DEBUGGING.md](DEBUGGING.md) — Detailed troubleshooting
