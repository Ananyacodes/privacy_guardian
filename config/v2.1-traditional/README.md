# Traditional Installation Configuration Files (v2.1)

This directory contains configuration files for Privacy Guardian v2.1 (traditional Raspberry Pi OS installation).

## Files

- **hostapd.conf** — Wi-Fi access point configuration
- **dnsmasq.conf** — DHCP server configuration
- **nftables.conf** — Firewall rules
- **dhcpcd.conf** — Network interface configuration
- **99-privacy-guardian.conf** — Kernel hardening (sysctl)
- **adguard-setup.conf** — AdGuard Home setup guide

## ⚠️ Deprecation Notice

Version 2.1 is **no longer actively maintained**.

**We recommend upgrading to v3.0 (Docker)** which provides:

- Automatic container isolation
- Easy updates & rollbacks
- Better resource management
- Simplified deployment

## Migration

See [MIGRATION.md](../../docs/deployment/MIGRATION.md) for v2.1 → v3.0 migration guide.

## For v2.1 Users

If you need to use v2.1, this config is kept for reference. Installation via:

```bash
sudo ./scripts/install/install.sh
```

**See:** [DEPLOYMENT_TRADITIONAL.md](../../docs/deployment/DEPLOYMENT_TRADITIONAL.md)
