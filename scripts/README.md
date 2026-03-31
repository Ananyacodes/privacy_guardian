# Scripts Directory

All shell scripts for installation, management, and maintenance.

## Directory Structure

### install/

- **install.sh** — Traditional Raspberry Pi OS installer (v2.1, deprecated)
- **install-docker.sh** — Docker deployment helper

### management/

- **pg-manage.sh** — Main management CLI for runtime operations
- **pg-test.sh** — Diagnostic tests and validators

### maintenance/

- **update-trackers.sh** — Daily tracker IP blocklist refresh
- **update-doh-ips.sh** — Monthly DoH resolver IP checker
- **disable-ipv6.sh** — IPv6 disabler (alternative configuration)

## Usage

```bash
# Management
sudo ./scripts/management/pg-manage.sh status
sudo ./scripts/management/pg-test.sh

# Maintenance (automated via cron)
sudo ./scripts/maintenance/update-trackers.sh
```

## Documentation

See [MANAGEMENT_CLI.md](../docs/management/MANAGEMENT_CLI.md) for full reference.
