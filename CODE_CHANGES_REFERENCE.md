# Privacy Guardian Frontend Integration - Code Changes Reference

Quick reference for all modifications made to integrate the UI dashboard.

---

## 1. docker-compose.yml Changes

**Location**: Added new service after `pg-hostapd`

**Addition** (Lines ~95-130):

```yaml
# ─────────────────────────────────────────────────────────────────────────
# NGINX UI — Router Dashboard Frontend
# ─────────────────────────────────────────────────────────────────────────
pg-ui:
  image: nginx:alpine
  container_name: pg-ui
  hostname: privacy-guardian-ui

  # Port mappings
  ports:
    - "8080:80"

  # Volumes
  volumes:
    - ./docs/ui:/usr/share/nginx/html:ro
    - ./nginx.conf:/etc/nginx/nginx.conf:ro

  # Restart policy
  restart: unless-stopped

  # Depends on AdGuard for API calls
  depends_on:
    - pg-adguard

  # Health check
  healthcheck:
    test: ["CMD", "wget", "-q", "-O-", "http://localhost"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 10s

  # Environment
  environment:
    - TZ=UTC
```

---

## 2. nginx.conf - New File

**Location**: `nginx.conf` at project root  
**Status**: CREATE (new file)

Key sections:

- Worker processes: auto (scales to CPU count)
- Upstream: Routes to pg-adguard:3000
- Server block with:
  - Static file serving with caching
  - API reverse proxy at `/api/adguard/*`
  - SPA routing (all to index.html)
  - Security headers and denials

---

## 3. docs/ui/js/config.js - New File

**Location**: `docs/ui/js/config.js`  
**Status**: CREATE (new file)

Exports:

```javascript
CONFIG = {
  api: {
    /* API endpoints */
  },
  fetchOptions: {
    /* Default fetch headers */
  },
  timeouts: {
    /* Request timeouts */
  },
  cache: {
    /* Cache configuration */
  },
  debug: {
    /* Debug settings */
  },
};

// Helper functions:
getApiUrl(endpoint, service);
fetchWithTimeout(url, options, timeout);
getCachedData(key, fetcher);
```

---

## 4. docs/ui/index.html Changes

**Location**: Bottom of file before closing `</body>`

**BEFORE**:

```html
    <section class="panel muted">
      <h2>Guest Network</h2>
      <p>Intentionally omitted in this build. Your current flow does not require guest network management.</p>
    </section>
  </main>

  <script src="app.js"></script>
</body>
</html>
```

**AFTER**:

```html
    <section class="panel muted">
      <h2>Guest Network</h2>
      <p>Intentionally omitted in this build. Your current flow does not require guest network management.</p>
    </section>
  </main>

  <!-- API Configuration -->
  <script src="js/config.js"></script>
  <!-- Dashboard Application -->
  <script src="app.js"></script>
</body>
</html>
```

---

## 5. docs/ui/app.js Changes - Part 1: Data Loading

**Location**: Top of file, replacing original `loadData()` function

**BEFORE**:

```javascript
const fallbackData = {
  generated_at: new Date().toISOString(),
  dashboard: {
    internet: { up: true, wan_ip: "10.0.0.28" },
    security: {
      /* ... */
    },
    counts: {
      /* ... */
    },
  },
  wifi_setup_steps: [
    /* ... */
  ],
  devices: [
    /* hardcoded device list */
  ],
};

async function loadData() {
  try {
    const res = await fetch("data/runtime.json", { cache: "no-store" });
    if (!res.ok) throw new Error("runtime.json not found");
    return await res.json();
  } catch (err) {
    return fallbackData;
  }
}
```

**AFTER**:

```javascript
const fallbackData = {
  generated_at: new Date().toISOString(),
  dashboard: {
    internet: { up: true, wan_ip: "192.168.4.1" },
    security: {
      /* same */
    },
    counts: {
      /* same */
    },
  },
  wifi_setup_steps: [
    /* same */
  ],
  devices: [], // Empty instead of hardcoded
  stats: {
    dns_queries: 0,
    blocked_queries: 0,
    blocked_percentage: 0,
    time_updated: 0,
  },
};

// New API functions
async function fetchAdGuardStats() {
  try {
    const url = getApiUrl("stats", "adguard");
    if (!url) throw new Error("Invalid API URL");
    const response = await fetchWithTimeout(url, {}, CONFIG.timeouts.stats);
    if (!response.ok) {
      console.warn(`AdGuard stats API returned ${response.status}`);
      return null;
    }
    const stats = await response.json();
    return {
      dns_queries: stats.dns_queries || 0,
      blocked_queries: stats.blocked_queries || 0,
      blocked_percentage: stats.blocked_percentage || 0,
      time_updated: Math.floor(Date.now() / 1000),
    };
  } catch (err) {
    console.error("[AdGuard Stats] Failed to fetch:", err.message);
    return null;
  }
}

async function fetchAdGuardQueryLog(limit = 100) {
  try {
    const url = CONFIG.api.adguard.baseUrl + "/querylog?limit=" + limit;
    const response = await fetchWithTimeout(url, {}, CONFIG.timeouts.querylog);
    if (!response.ok) return [];
    const data = await response.json();
    return data.data || [];
  } catch (err) {
    console.error("[AdGuard QueryLog] Failed to fetch:", err.message);
    return [];
  }
}

async function fetchTopBlockedDomains(limit = 10) {
  try {
    const url =
      CONFIG.api.adguard.baseUrl + "/stats/top_blocked_domains?limit=" + limit;
    const response = await fetchWithTimeout(url, {}, CONFIG.timeouts.stats);
    if (!response.ok) return [];
    const data = await response.json();
    return data || [];
  } catch (err) {
    console.error("[AdGuard Top Blocked] Failed to fetch:", err.message);
    return [];
  }
}

// New multi-source loadData function
async function loadData() {
  let data = JSON.parse(JSON.stringify(fallbackData));

  // Try to fetch from AdGuard API first
  const adguardStats = await fetchAdGuardStats();
  if (adguardStats) {
    data.stats = adguardStats;
    data.dashboard.security.adguard_active = true;
  } else {
    data.dashboard.security.adguard_active = false;
  }

  // Try runtime.json as secondary data source
  try {
    const res = await fetch("data/runtime.json", { cache: "no-store" });
    if (res.ok) {
      const runtimeData = await res.json();
      if (runtimeData.devices) data.devices = runtimeData.devices;
      if (runtimeData.dashboard)
        data.dashboard = { ...data.dashboard, ...runtimeData.dashboard };
      if (runtimeData.stats)
        data.stats = { ...data.stats, ...runtimeData.stats };
    }
  } catch (err) {
    console.warn("[runtime.json] Not found or error loading:", err.message);
  }

  // Calculate device counts
  if (data.devices && data.devices.length > 0) {
    const counts = { iot: 0, personal: 0, public: 0, unknown: 0 };
    data.devices.forEach((d) => {
      const category = d.category || "unknown";
      if (category in counts) counts[category]++;
    });
    data.dashboard.counts = { ...counts, total_devices: data.devices.length };
  }

  data.generated_at = new Date().toISOString();
  return data;
}
```

---

## 6. docs/ui/app.js Changes - Part 2: Rendering

**Location**: `renderStatusCards()` function

**BEFORE**:

```javascript
function renderStatusCards(data) {
  const cards = document.getElementById("statusCards");
  const security = data.dashboard.security;
  cards.innerHTML = [
    card("Internet", data.dashboard.internet.up ? "Online" : "Offline"),
    card("WAN IP", data.dashboard.internet.wan_ip || "Unknown"),
    card("Total Devices", data.dashboard.counts.total_devices),
    card("Protection", security.zone_protection || "Unknown"),
  ].join("");
}
```

**AFTER**:

```javascript
function renderStatusCards(data) {
  const cards = document.getElementById("statusCards");
  const security = data.dashboard.security;

  // Format DNS blocked percentage
  const blockedPct =
    data.stats && data.stats.blocked_percentage
      ? `${Math.round(data.stats.blocked_percentage * 10) / 10}%`
      : "N/A";

  cards.innerHTML = [
    card("Internet", data.dashboard.internet.up ? "Online" : "Offline"),
    card("WAN IP", data.dashboard.internet.wan_ip || "Unknown"),
    card("Total Devices", data.dashboard.counts.total_devices),
    card("DNS Blocked", blockedPct),
  ].join("");
}
```

**Other render functions**: No changes needed (all compatible)

---

## Deployment Checklist

```bash
# 1. Verify file structure
ls -la nginx.conf                           # Should exist
ls -la docs/ui/js/config.js                 # Should exist
grep "pg-ui:" docker-compose.yml            # Should find new service

# 2. Validate configs
docker compose config | grep -A 30 "pg-ui"  # Validate YAML
nginx -t -c $(pwd)/nginx.conf               # Validate Nginx (if installed locally)

# 3. Start services
docker compose up -d

# 4. Verify running
docker compose ps | grep pg-ui              # Should show running

# 5. Test endpoints
curl http://localhost:8080                  # Should return HTML
curl http://localhost:8080/index.html       # Should return UI
curl http://localhost:8080/api/adguard/stats # Should proxy to AdGuard
```

---

## Summary of Changes

| File                 | Type     | Lines Changed | Purpose                     |
| -------------------- | -------- | ------------- | --------------------------- |
| docker-compose.yml   | Modified | +45           | Added pg-ui service         |
| nginx.conf           | Created  | 130           | Reverse proxy config        |
| docs/ui/js/config.js | Created  | 180           | API config & helpers        |
| docs/ui/app.js       | Modified | +120          | API integration             |
| docs/ui/index.html   | Modified | +2            | Added config.js import      |
| **TOTAL**            | -        | **+377**      | **Complete UI integration** |

---

## Testing Script

Save as `test-ui-integration.sh`:

```bash
#!/bin/bash

echo "Testing Privacy Guardian UI Integration..."

# 1. Check Docker
echo "1. Checking Docker services..."
docker compose ps | grep -E "pg-ui|pg-adguard" || echo "ERROR: Services not running"

# 2. Test Nginx
echo "2. Testing Nginx..."
curl -s http://localhost:8080/ | grep -q "Privacy Guardian" && echo "✓ Nginx serving UI" || echo "✗ Nginx failed"

# 3. Test static assets
echo "3. Testing static assets..."
curl -s http://localhost:8080/styles.css | grep -q "root" && echo "✓ CSS loaded" || echo "✗ CSS failed"
curl -s http://localhost:8080/app.js | grep -q "loadData" && echo "✓ JS loaded" || echo "✗ JS failed"

# 4. Test config
echo "4. Testing config..."
curl -s http://localhost:8080/js/config.js | grep -q "CONFIG" && echo "✓ Config loaded" || echo "✗ Config failed"

# 5. Test reverse proxy
echo "5. Testing reverse proxy..."
curl -s http://localhost:8080/api/adguard/stats | grep -q "dns_queries" && echo "✓ API proxy works" || echo "✗ API proxy failed"

echo "Done!"
```

---

## Rollback Instructions

If needed to rollback:

```bash
# 1. Stop services
docker compose down

# 2. Remove new files
rm nginx.conf
rm -rf docs/ui/js

# 3. Restore original docker-compose.yml
git checkout docker-compose.yml

# 4. Restore original app.js and index.html
git checkout docs/ui/app.js
git checkout docs/ui/index.html

# 5. Restart
docker compose up -d
```

---

## Git Commit Message

```
feat: integrate frontend UI as main router dashboard

- Add pg-ui service (Nginx) to docker-compose.yml
- Create nginx.conf with reverse proxy for AdGuard API
- Create docs/ui/js/config.js for API configuration
- Update docs/ui/app.js to fetch data from AdGuard API
- Update docs/ui/index.html to load config.js
- UI accessible at http://<pi-ip>:8080
- Full fallback support for offline mode
- No breaking changes to existing containers

Fixes: #1 (UI integration task)
```

---

**All changes documented and ready for deployment!**
