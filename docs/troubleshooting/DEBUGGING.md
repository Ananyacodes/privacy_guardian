# Debugging Guide

Step-by-step procedures for troubleshooting Privacy Guardian issues.

## Quick Diagnostics

### 1. Run Built-In Tests

```bash
sudo ./scripts/management/pg-test.sh
```

This runs comprehensive checks:

- Network connectivity
- DNS resolution
- Service health
- Firewall rules
- IPv6 configuration

### 2. Check Service Status

```bash
docker compose ps

# Expected output:
# CONTAINER ID   NAMES                       STATUS
# xxx            privacy-guardian-hostapd    Up 2 days
# yyy            privacy-guardian-dnsmasq    Up 2 days
# zzz            privacy-guardian-firewall   Up 2 days
```

### 3. View Recent Logs

```bash
docker compose logs --tail=50 -t
```

---

## Enable Debug Logging

### AdGuard Home

1. Visit http://192.168.4.1:3000
2. Settings → General → Query Logs
3. Enable: "Write query log to file"
4. Set log level to DEBUG

### nftables

```bash
# Enable kernel debug logging
echo 1 | sudo tee /proc/sys/net/netfilter/nf_log/2

# View debug logs
sudo tail -f /var/log/messages | grep -i nft

# Or using dmesg
sudo dmesg -w | grep -i nft
```

### hostapd

Edit `config/v3.0-docker/hostapd.conf`:

```
# Add debug line
logger_syslog_level=1
logger_syslog_facility=LOG_LOCAL7
debug=2
```

Restart:

```bash
docker compose restart hostapd
```

### dnsmasq

Edit `config/v3.0-docker/dnsmasq.conf`:

```
# Add debug line
log-queries=extra
log-facility=/var/log/dnsmasq.log
```

Restart:

```bash
docker compose restart dnsmasq
```

---

## Common Issues

### Issue: No WAN Connectivity

**Symptoms:** Can't reach Internet, ping 8.8.8.8 fails

**Debugging Steps:**

```bash
# 1. Check eth0 is up
ip addr show eth0
# Should show: inet 203.x.x.x/xx

# 2. Check default route
ip route
# Should show: default via 192.168.1.1 dev eth0

# 3. Test gateway
ping 192.168.1.1

# 4. Check firewall isn't blocking
sudo nft list chain inet filter forward | head -20

# 5. Check eth0 is in correct zone
sudo nft list table inet filter
```

**Solutions:**

- Restart firewall: `docker compose restart firewall`
- Check cable connection
- Verify upstream router is reachable: `ping -c 3 192.168.1.1`

---

### Issue: No LAN Connectivity / Devices Can't Connect

**Symptoms:** Wi-Fi shows up but fails to connect, no DHCP offer

**Debugging Steps:**

```bash
# 1. Check wlan0 interface
ip link show wlan0
# Should show: UP, BROADCAST, RUNNING

# 2. Check wlan0 IP
ip addr show wlan0
# Should show: inet 192.168.4.1/24

# 3. Check hostapd is running
docker compose logs -f hostapd --tail=20

# 4. Check Wi-Fi network is broadcasting
sudo iw dev wlan0 link
# Should show: connected (or "Not connected")

# 5. Verify SSID
sudo iw dev wlan0 scan | grep SSID
```

**Solutions:**

- Restart hostapd: `docker compose restart hostapd`
- Check password is correct: `.env` file
- Check channel conflicts: `sudo iw dev wlan0 survey dump`

---

### Issue: DNS Not Working

**Symptoms:** `Unknown host` errors, websites won't load

**Debugging Steps:**

```bash
# 1. Test direct DNS query
nslookup google.com 192.168.4.1
# Should return IP

# 2. Check AdGuard is running
curl -s http://localhost:3000/health | jq '.'

# 3. Check DNS redirect rule
sudo nft list chain inet nat prerouting | grep -A3 dns

# 4. Test from connected device
# From any connected device:
nslookup google.com 192.168.4.1

# 5. Check upstream DNS
dig @9.9.9.9 google.com

# 6. Monitor AdGuard logs
curl -s 'http://localhost:3000/api/logs' | jq '.data | last'
```

**Solutions:**

- Restart firewall: `docker compose restart firewall`
- Check AdGuard service: `docker compose restart adguard` (if running separately)
- Verify upstream DNS is reachable
- Check port 53: `sudo netstat -tlnp | grep :53`

---

### Issue: DNS Queries Leaking Out

**Symptoms:** DNS leak tests show public DNS, not AdGuard

**Debugging Steps:**

```bash
# 1. Check nftables redirect rule exists
sudo nft list chain inet nat prerouting

# 2. Test redirect manually
sudo tcpdump -i any port 53 -A
# Then from another device: nslookup google.com

# 3. Check AdGuard is listening
sudo netstat -tlnp | grep :53

# 4. Verify devices are using 192.168.4.1
# From connected device:
cat /etc/resolv.conf
# Should show: nameserver 192.168.4.1

# 5. Monitor in real-time
sudo tcpdump -i wlan0 -n 'udp port 53'
```

**Solutions:**

- Reload firewall: `sudo pg-manage.sh reload`
- Check `nftables.conf` has DNS redirect rules
- Verify gateway is set correctly in DHCP

---

### Issue: DoH/DoT Bypass Detected

**Symptoms:** Device uses HTTPS DNS despite firewall, bypasses AdGuard

**Debugging Steps:**

```bash
# 1. Check blocked IPs are in nftables set
sudo nft list set inet filter doh_resolvers
sudo nft list set inet filter dot_resolvers

# 2. Monitor traffic to known DoH IPs
sudo tcpdump -i eth0 -n 'dst port 443 or dst port 8853'
# Should show: packets being dropped

# 3. Check nftables rules are enabled
sudo nft list chain inet filter privacy_chain | grep -E "443|8853"

# 4. Test with curl
curl --doh-url https://1.1.1.1/dns-query https://example.com
# Should fail if firewall is working
```

**Solutions:**

- Update DoH/DoT IP lists: `sudo pg-manage.sh update doh`
- Verify nftables rules loaded: `sudo nft list ruleset | wc -l`
- Check firewall restart: `docker compose restart firewall`

---

### Issue: IPv6 Leaks

**Symptoms:** IPv6 address visible in leak tests

**Debugging Steps:**

```bash
# 1. Check IPv6 is enabled
ip addr show | grep inet6

# 2. Check ULA prefix
ip addr | grep -i ula
# Should show: fd00::/8 range

# 3. Test IPv6 connectivity
ping6 2001:4860:4860::8888
# Should be blocked or show response through ULA

# 4. Check nftables IPv6 rules
sudo nft list table ip6 filter
```

**Solutions:**

- Disable IPv6 entirely: See [ARCHITECTURE.md](../architecture/ARCHITECTURE.md#ipv6-handling)
- Or configure properly: Check `nftables.conf` IPv6 section

---

### Issue: High CPU/Memory Usage

**Symptoms:** Pi gets hot, processes slow, system response sluggish

**Debugging Steps:**

```bash
# 1. Check which service is using most resources
docker stats

# 2. Monitor in detail
top
# Press 'q' to quit

# 3. Check if out of disk space (cause memory issues)
df -h
free -h

# 4. Check for memory leaks
# Monitor over 10+ minutes
watch -n 5 'docker stats --no-stream'

# 5. Check for high query load
sudo pg-manage.sh stats

# 6. Check firewall rule count (can slow down packet processing)
sudo nft list ruleset | wc -l
```

**Solutions:**

- Reduce blocklist size in AdGuard
- Disable DNSSEC if not needed
- Restart services: `docker compose restart`
- Upgrade to Pi 4 if using Pi 3B
- Check for rogue queries: `sudo pg-manage.sh blocked`

---

### Issue: DHCP Leases Not Assigned

**Symptoms:** Devices connect to Wi-Fi but don't get IP addresses

**Debugging Steps:**

```bash
# 1. Check dnsmasq is running
docker compose ps | grep dnsmasq

# 2. Check DHCP config
cat config/v3.0-docker/dnsmasq.conf | grep -A3 "dhcp-range"

# 3. Check DHCP logs
docker compose logs dnsmasq | grep -i dhcp

# 4. Monitor DHCP traffic
sudo tcpdump -i wlan0 -n 'dhcp or port 67 or port 68'

# 5. Check IP pool
ip route show
```

**Solutions:**

- Verify DHCP range is correct
- Device might have cached lease, forget network and reconnect
- Restart dnsmasq: `docker compose restart dnsmasq`
- Check no conflicting DHCP server on network

---

## Deep Debugging

### Enable tcpdump Monitoring

```bash
# Monitor all DNS queries
sudo tcpdump -i any -n 'port 53'

# Monitor Wi-Fi only
sudo tcpdump -i wlan0 -A -s 0

# Monitor with output to file
sudo tcpdump -i any -w /tmp/capture.pcap
# Then analyze: wireshark /tmp/capture.pcap
```

### Check Firewall Rules in Detail

```bash
# List all tables
sudo nft list tables

# List specific table
sudo nft list table inet filter

# Count rules
sudo nft list ruleset | wc -l

# Count set entries (blocked IPs)
sudo nft list set inet filter tracker_ips | wc -l
```

### View Container Internals

```bash
# Shell into container
docker exec -it privacy-guardian-firewall /bin/bash

# View system info inside
uname -a
/sbin/nft list ruleset

# Check connectivity from container
ping 8.8.8.8
```

### Check System Logs

```bash
# Kernel messages
dmesg | tail -50

# System log
tail -f /var/log/syslog

# Docker daemon log
journalctl -u docker.service -f
```

---

## Performance Analysis

### Identify Slow DNS Queries

```bash
# Monitor query response times
curl -s 'http://localhost:3000/logs' | jq '.data[] | select(.response_time > 100) | {domain, response_time}'
```

### Check Bottlenecks

```bash
# Disk I/O
iostat -x 1 5

# Network I/O
nethogs

# Memory pressure
vmstat 1 5
```

### Profile Specific Service

```bash
# CPU profile hostapd
docker exec privacy-guardian-hostapd ps aux | grep hostapd

# Memory profile
docker exec privacy-guardian-firewall free -h

# Network stats
docker exec privacy-guardian-firewall ip -s link
```

---

## Collecting Debug Information for Support

```bash
# Create debug bundle
mkdir /tmp/pg-debug
cd /tmp/pg-debug

# Gather info
docker compose ps > docker-ps.txt
docker compose logs --tail=500 > docker-logs.txt
sudo nft list ruleset > nftables.txt
sudo pg-manage.sh status > pg-status.txt
sudo pg-manage.sh stats > pg-stats.txt
uname -a > system-info.txt

# Sanitize sensitive data
sed -i 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/XXX.XXX.XXX.XXX/g' *.txt

# Create tarball
tar -czf privacy-guardian-debug.tar.gz *.txt

# Share with maintainer
```

---

## Getting Help

When reporting issues:

1. Include output from `pg-test.sh`
2. Include relevant log sections (sanitized)
3. Describe what you tried
4. Include hardware specs (Pi model, OS version)
5. Include reproduction steps

See [FAQ.md](FAQ.md) for more help.
