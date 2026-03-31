# Frequently Asked Questions

## General

### Q: What's the difference between v2.1 and v3.0?

**A:** v2.1 is the traditional Raspberry Pi OS installation that directly modifies system files. v3.0 uses Docker Compose for containerized deployment which is easier to maintain, update, and rollback.

**Recommendation:** Use v3.0 (Docker) for new installations.

### Q: Can I run this on a Raspberry Pi 3?

**A:** Yes, but performance will be limited. Pi 3B+ is minimum supported; Pi 4 (2GB) is recommended.

### Q: Does this work on non-Raspberry Pi devices?

**A:** Yes! Any system with Docker (Linux, macOS via Colima, Windows via WSL2) will work.

---

## Setup & Deployment

### Q: Where do I get the Raspberry Pi OS image?

**A:** Download from https://www.raspberrypi.com/software/

Use **Raspberry Pi OS Lite (64-bit Bookworm)** for best results.

### Q: How do I enable SSH before first boot?

**A:** Create an empty file named `ssh` in the boot partition after flashing:

```bash
# On Linux/macOS
touch /Volumes/boot/ssh

# On Windows (using Command Prompt as Admin)
type nul > E:\ssh
```

### Q: Docker won't start. What should I do?

**A:** Check the installation:

```bash
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

docker --version
docker-compose --version
```

### Q: Port 53 is already in use. What's the conflict?

**A:** Check what's using port 53:

```bash
sudo netstat -tlnp | grep :53
sudo lsof -i :53
```

If systemd-resolved is running:

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

---

## Network & Connectivity

### Q: Devices can't connect to the Wi-Fi

**A:** Check if hostapd is running:

```bash
# Check logs
docker compose logs hostapd

# List available networks
sudo iwlist wlan0 scan

# Check interface status
ip link show wlan0
```

### Q: Connected, but no internet

**A:** Run diagnostics:

```bash
# From Pi
ping 8.8.8.8  # Check WAN
ping 192.168.4.1  # Check gateway
nslookup google.com 192.168.4.1  # Check DNS

# From connected device
nslookup 8.8.8.8  # Reverse DNS
```

### Q: Losing connection randomly

**A:** Check system logs:

```bash
# Check for OOM (out of memory)
docker compose logs firewall | grep -i "oom\|kill"

# Monitor resources
docker stats

# Check Wi-Fi signal/interference
sudo iw wlan0 station dump
```

### Q: Can't reach AdGuard UI (http://192.168.4.1:3000)

**A:**

- Check from **admin device only** (IP whitelist enforced)
- Verify AdGuard is running: `docker ps | grep adguard`
- Check firewall rules: `sudo nft list ruleset | grep 3000`

---

## DNS & Blocking

### Q: DNS leak test shows public DNS servers, not AdGuard

**A:** DNS redirect isn't working. Check:

```bash
# Test if redirect is active
nslookup google.com 192.168.4.1
nslookup google.com 8.8.8.8  # Should timeout/fail

# Check nftables rules
sudo nft list chain inet nat prerouting | grep -A5 dns
```

### Q: Some sites are blocked but shouldn't be

**A:**

1. Check AdGuard logs: http://192.168.4.1:3000/logs
2. Find the domain causing false positive
3. Whitelist it: `sudo pg-manage.sh whitelist example.com`

### Q: Ads/tracking still appearing

**A:**

- Update blocklists in AdGuard UI
- Check AdGuard is actually filtering (look at query logs)
- Some apps have hardcoded IPs (not blockable at DNS level)

### Q: DNSSEC validation failures

**A:** Check upstream DNS supports DNSSEC:

```bash
# Test DNSSEC
dig example.com @192.168.4.1 +dnssec

# Check AdGuard settings
# → Settings → Upstream DNS → Select DNSSEC-supporting resolver
```

---

## Performance

### Q: Router is slow/sluggish

**A:** Check resource usage:

```bash
docker stats

# If memory full
docker compose down
docker system prune -a
docker compose up -d
```

### Q: High CPU usage

**A:**

- Check query load: `sudo pg-manage.sh blocked | tail -20`
- Disable DNSSEC if not needed
- Reduce blocklist count in AdGuard

### Q: DNS queries timing out

**A:**

- Check firewall rules aren't dropping packets
- Check AdGuard is responsive: `curl -s http://localhost:3000/health`
- Check upstream DNS: `dig @9.9.9.9 google.com`

---

## Security

### Q: How do I change Wi-Fi password?

**A:** Edit `.env`:

```bash
WPA_PASSPHRASE=NewStrongPassword
docker compose restart hostapd
```

### Q: Can I restrict Wi-Fi to specific devices?

**A:** Yes, via MAC filtering in `config/v3.0-docker/hostapd.conf`:

```
macaddr_acl=1
accept_mac_file=/etc/hostapd/accept_mac
```

See [HOSTAPD.md](../configuration/HOSTAPD.md)

### Q: How do I SSH to the Pi without the router breaking the connection?

**A:** Make sure your admin device is whitelisted:

```bash
# Set ADMIN_IP in .env
ADMIN_IP=192.168.1.100
docker compose restart firewall
```

### Q: Is IPv6 private by default?

**A:** Yes. IPv6 uses ULA (fd00::/8) which is private. To disable fully:

```bash
# Uncomment IPv6 disable sections in nftables.conf
docker compose restart firewall
```

---

## Logging & Debugging

### Q: Where are logs stored?

**A:** In Docker:

```bash
# View all logs
docker compose logs

# Follow logs in real-time
docker compose logs -f

# Specific service
docker compose logs -f hostapd
```

### Q: How do I enable debug mode?

**A:** See [DEBUGGING.md](DEBUGGING.md)

### Q: How do I backup my configuration?

**A:**

```bash
# Using management CLI
sudo pg-manage.sh backup

# Or manually
docker cp privacy-guardian-hostapd-1:/etc/hostapd ./backup/
```

---

## Docker-Specific

### Q: How do I update to the latest version?

**A:**

```bash
git pull
docker compose pull
docker compose up -d
```

### Q: What if a container crashes?

**A:** Docker will auto-restart. Check logs:

```bash
docker compose logs <service_name>
docker compose restart <service_name>
```

### Q: Can I run multiple Privacy Guardian instances?

**A:** Not on the same Pi (port conflicts). On different hosts: yes.

### Q: How do I remove Privacy Guardian?

**A:**

```bash
docker compose down
docker system prune -a
rm -rf ~/privacy_guardian/
```

---

## Migration from v2.1

### Q: Can I upgrade from v2.1 to v3.0 in place?

**A:** Not recommended. See [MIGRATION.md](../deployment/MIGRATION.md)

### Q: Will I lose my blocklist configuration?

**A:** No, export from old AdGuard, import to new.

---

## Getting Help

1. **Check logs:** `docker compose logs`
2. **Run diagnostics:** `sudo pg-test.sh`
3. **Search existing issues:** GitHub Issues
4. **Enable debug:** See [DEBUGGING.md](DEBUGGING.md)
5. **Report issue:** Include logs + config (sanitized)

---

## See Also

- [DEBUGGING.md](DEBUGGING.md) — Detailed troubleshooting
- [NETWORK_ISSUES.md](NETWORK_ISSUES.md) — Connectivity problems
- [DEPLOYMENT_DOCKER.md](../deployment/DEPLOYMENT_DOCKER.md) — Setup guide
