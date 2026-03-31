# Docker Files

Dockerfiles for Privacy Guardian services.

## Services

- **Dockerfile.hostapd** — Wi-Fi access point container
- **Dockerfile.dnsmasq** — DHCP server container
- **Dockerfile.firewall** — Firewall (nftables) container (--privileged)
- **Dockerfile.nginx** — Optional reverse proxy container

## Building

Images are built automatically by `docker compose`:

```bash
# Build all services
docker compose build

# Build specific service
docker compose build hostapd
```

## See Also

- [docker-compose.yml](../docker-compose.yml) — Service orchestration
- [DEPLOYMENT_DOCKER.md](../docs/deployment/DEPLOYMENT_DOCKER.md) — Setup guide
