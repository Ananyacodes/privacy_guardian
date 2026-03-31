# System Architecture

Complete overview of Privacy Guardian's architecture, components, and data flow.

## System Overview

```
Internet
├──eth0──────[Firewall nftables]────────────────────┐
│            (IPv4 + IPv6 filtering)                │
│                    │                              │
│            ┌───────┴────────┐                     │
│            │                │                     │
│       [Redirect]      [Allow/Block]               │
│            │                │                     │
│            ▼                ▼                      │
│       [AdGuard Home]   [NAT Masquerade]           │
│         (:53 DNS)     (192.168.4.0/24)            │
│            │                │                     │
│       [DNSSEC]         [Device Isolation]         │
│       [Blocklists]                                │
│            │                │                     │
└────────────┼────────────────┼────────────────────┐
             │                │
          wlan0 (192.168.4.0/24)
             │
    ┌────────┴────────┐
    │                 │
Connected Devices  Admin Device
```

## Component Architecture

### 1. Firewall (nftables)

**Location:** `Dockerfile.firewall` / `nftables.conf`

**Responsibilities:**

- Packet filtering (stateful inspection)
- DNS redirect (prerouting)
- NAT masquerade
- Tracker IP blocking
- DoH/DoT blocking on specific ports
- IPv6 privacy & ULA routing

**Network Stack:**

```
eth0 (WAN)
  ↓
[nftables ingress]
  │
  ├─ Prerouting (nat) → Redirect :53 UDP to AdGuard
  ├─ Forward (filter) → Allow/drop packets
  │   ├─ Block DoH (:443 to known resolver IPs)
  │   ├─ Block DoT (:853)
  │   ├─ Block DoQ (:8853)
  │   └─ Allow established connections
  ├─ Postrouting (nat) → Masquerade 192.168.4.0/24
  │
wlan0 (LAN)
```

### 2. DNS Filtering (AdGuard Home)

**Location:** External service (not containerized in base setup)

**Responsibilities:**

- Domain-based blocking (blocklists)
- DNS query logging
- DNSSEC validation
- Upstream DNS resolution
- Admin dashboard

**Query Flow:**

```
Device DNS Query (192.168.4.5:12345 → 192.168.4.1:53)
  ↓
nftables REDIRECT
  ↓
AdGuard Home (:53)
  │
  ├─ Check blocklists → BLOCKED (NXDOMAIN)
  ├─ Or upstream → Quad9/Cloudflare
  │
Response (192.168.4.1:53 → 192.168.4.5:12345)
```

### 3. DHCP Server (dnsmasq)

**Location:** `Dockerfile.dnsmasq` / `dnsmasq.conf`

**Responsibilities:**

- IP address assignment (192.168.4.10 - 192.168.4.200)
- DHCP leases
- DNS forwarding (to AdGuard, not resolving)
- Device discovery

**DHCP Lease Lifecycle:**

```
Device DHCP DISCOVER
  ↓
dnsmasq (192.168.4.1)
  │
  ├─ Assign IP from pool
  ├─ Set gateway: 192.168.4.1
  ├─ Set DNS: 192.168.4.1 (AdGuard)
  │
Device DHCP ACK → Ready to use
```

### 4. Wi-Fi Access Point (hostapd)

**Location:** `Dockerfile.hostapd` / `hostapd.conf`

**Responsibilities:**

- Broadcast SSID
- Handle Wi-Fi authentication (WPA2/WPA3)
- Bridge traffic to wlan0 interface
- Client association

**Wi-Fi Configuration:**

```
hostapd (::: broadcast PrivacyGuardian SSID)
  │
  ├─ SSID: PrivacyGuardian
  ├─ Channel: Auto (2.4GHz + 5GHz)
  ├─ WPA: WPA2-PSK / WPA3
  ├─ Cipher: CCMP (AES)
  │
wlan0 interface
  │
Connected Clients (WPA handshake)
```

## Data Flow

### A. Internet → Device (Incoming)

```
Internet (e.g., 8.8.8.8 wants to reach device on 192.168.4.5)
  ↓ (packets destined for device public IP)
eth0 (WAN interface)
  ↓
nftables POSTROUTING (nat)
  │ (reverse masquerade: public IP → 192.168.4.5)
  ↓
wlan0 (LAN interface)
  ↓
192.168.4.5 (device receives packet)
```

**Note:** Return path is automatic (established connection tracking)

### B. Device → Internet (Outgoing)

```
Device (192.168.4.5) uploads to AWS S3
  ↓ (packet: src=192.168.4.5:random_port, dst=52.x.x.x:443)
wlan0 (LAN interface)
  ↓
nftables PREROUTING (filter) → check if ESTABLISHED
  ↓
nftables FORWARD → allow established
  ↓
nftables POSTROUTING (nat) → MASQUERADE
  │ (rewrite: src=192.168.4.5 → src=eth0_WAN_IP)
  ↓
eth0 (WAN interface)
  ↓
Internet sees only your Pi's WAN IP
```

### C. DNS Query (Via AdGuard)

```
Device (192.168.4.5:53 → tracking.example.com)
  ↓ (UDP DNS query)
nftables PREROUTING (nat)
  │ (REDIRECT: src port :53 → AdGuard process :53)
  ↓
AdGuard Home
  │
  ├─ Check blocklists
  │   ├─ tracking.example.com → Found in blocklist
  │   └─ Response: NXDOMAIN (blocked)
  │
  Or (if not blocked):
  │   ├─ Forward to upstream (Quad9)
  │   ├─ Receive response
  │   └─ Return to device
  ↓
Device receives DNS response
```

### D. DNS Bypass Prevention (DoH)

```
Device tries HTTPS DNS (1.1.1.1:443)
  ↓
wlan0 (packet: dst=1.1.1.1:443)
  ↓
nftables FORWARD (filter)
  │ (check if 1.1.1.1 is in doh_resolvers set)
  │ (DROP packet)
  ↓
Connection fails
Device falls back to 192.168.4.1:53 (AdGuard)
```

## Network Topology

```
┌─────────────────── Privacy Guardian (192.168.4.1) ─────────────────┐
│                                                                      │
│  Docker Host (Raspberry Pi)                                         │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                                                               │  │
│  │  [Container: firewall]                                      │  │
│  │  └─ nftables rules                                          │  │
│  │  └─ iptables rules (compat)                                 │  │
│  │                                                               │  │
│  │  [Container: hostapd]     [Container: dnsmasq]             │  │
│  │  └─ wlan0: PrivacyGuardian └─ DHCP server                  │  │
│  │  └─ WPA2/WPA3                └─ :67 (DHCP)                  │  │
│  │                              │  │                            │  │
│  │                              │  └─ Docker bridge network    │  │
│  │                              │                              │  │
│  │  [AdGuard Home]                                             │  │
│  │  └─ DNS filtering (:53)                                     │  │
│  │  └─ Admin UI (:3000)                                        │  │
│  │                                                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                          │                                           │
│         ┌────────────────┼────────────────┐                         │
│         │                                 │                         │
│      eth0 (WAN)                        wlan0 (LAN)                 │
│      ▼                                   ▼                         │
│  Upstream Router                  Connected Devices               │
│  (192.168.1.1)                   (192.168.4.2 - 4.200)             │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## IPv6 Handling

### Default: IPv6 Privacy (ULA Routing)

```
Device IPv6 request (e.g., AAAA lookup for example.com)
  ↓
AdGuard Home (handles)
  ↓
Response: IPv6 address
  ↓
Device sends to IPv6 address
  ↓
nftables OUTPUT (blocked unless internal ULA)
  └─ ULA range: fd00::/8 (private)
```

### Alternative: IPv6 Disabled

```bash
# Uncomment in nftables.conf:
# flush ip6 table filter
# flush ip6 table nat
docker compose restart firewall
```

## Container Networking

### Docker Compose Network

```yaml
networks:
  privnet:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16 # Internal Docker network
```

**Container IPs (internal):**

- firewall: 172.20.0.3
- hostapd: 172.20.0.4
- dnsmasq: 172.20.0.5

**External IPs (via host):**

- eth0: WAN IP (DHCP or static)
- wlan0: 192.168.4.1 (bridged from container)

## Resource Management

### CPU & Memory

```
hostapd:   ~1-2% CPU, 50MB RAM (varies by client count)
dnsmasq:   ~0.5-1% CPU, 20MB RAM
firewall:  ~2-5% CPU, 50MB RAM (packet processing)
AdGuard:   ~3-10% CPU, 100-200MB RAM (depends on blocklis count)
```

### Disk I/O

- query logs: ~10-50KB/hour (configurable retention)
- Configs: ~1MB total
- AdGuard DB: ~50-100MB (statistics)

## Security Model

### Privilege Separation

```
firewall container: --cap-add NET_ADMIN (required)
  └─ Can modify firewall rules

hostapd container: --cap-add NET_ADMIN (required)
  └─ Can manage Wi-Fi

dnsmasq container: No special caps
  └─ DHCP via unprivileged port binding

AdGuard Home: Runs as separate service (outside Docker)
  └─ Listens on port :3000 (admin), :53 (DNS)
```

### Network Isolation

```
wlan0 ← No direct host access
192.168.4.1/24 ← Isolated from host network
eth0 ← Only firewall container can modify
```

### Trusted Admin Device

```
ADMIN_IP (192.168.1.100)
  │
  └─ SSH access: YES
  └─ AdGuard UI: YES
  └─ Management CLI: YES

Other devices
  └─ SSH access: BLOCKED (nftables)
  └─ AdGuard UI: IP whitelist
  └─ Management CLI: ssh key required
```

## Extension Points

### Adding Custom Rules

Edit `config/v3.0-docker/nftables.conf`:

```bash
# Add to the privacy_chain
add rule inet filter privacy_chain ip daddr @bad_ips drop comment "Custom IP blocklist"
```

### Adding Blocklists

In AdGuard Home UI:

1. Filters → DNS Blocklists → Add List
2. Paste URL
3. Enable/disable as needed

### Custom Firewall Scripts

Add to `scripts/maintenance/`:

```bash
#!/bin/bash
# Custom update script
docker compose exec firewall nft add set inet filter custom_ips { ... }
```

Run via cron.

---

## See Also

- [NETWORK_DESIGN.md](NETWORK_DESIGN.md) — Detailed network topology
- [DATA_FLOW.md](DATA_FLOW.md) — Packet flow diagrams
- [NFTABLES.md](../configuration/NFTABLES.md) — Firewall rules
