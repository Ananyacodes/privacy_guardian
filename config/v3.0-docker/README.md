# Docker Configuration Files

This directory contains configuration files for Privacy Guardian v3.0 (Docker deployment).

## Files

- **hostapd.conf** — Wi-Fi access point configuration (2.4GHz/5GHz)
- **dnsmasq.conf** — DHCP server configuration
- **nftables.conf** — Firewall rules (IPv4 + IPv6)
- **dhcpcd.conf** — Network interface configuration
- **99-privacy-guardian.conf** — Kernel hardening (sysctl parameters)
- **adguard-setup.conf** — AdGuard Home setup & recommended blocklists

## Usage

These files are automatically mounted into Docker containers via `docker-compose.yml`:

```yaml
volumes:
  - ./config/v3.0-docker/hostapd.conf:/etc/hostapd/hostapd.conf:ro
  - ./config/v3.0-docker/dnsmasq.conf:/etc/dnsmasq.conf:ro
  # ... etc
```

## Customization

To modify settings:

1. Edit the desired `.conf` file
2. Restart the affected service:
   ```bash
   docker compose restart hostapd  # for hostapd.conf changes
   docker compose restart dnsmasq  # for dnsmasq.conf changes
   ```
3. Or restart all: `docker compose down && docker compose up -d`

## See Also

- [HOSTAPD.md](../../docs/configuration/HOSTAPD.md) — Detailed Wi-Fi settings
- [NFTABLES.md](../../docs/configuration/NFTABLES.md) — Firewall rules
- [ADGUARD.md](../../docs/configuration/ADGUARD.md) — DNS filtering
