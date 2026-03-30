/**
 * Privacy Guardian Dashboard
 * Integrates with AdGuard Home API for real-time stats and query logs
 */

const fallbackData = {
  generated_at: new Date().toISOString(),
  dashboard: {
    internet: { up: true, wan_ip: "192.168.4.1" },
    security: {
      firewall_active: true,
      adguard_active: true,
      hostapd_active: true,
      zone_protection: "strict"
    },
    counts: {
      total_devices: 0,
      iot: 0,
      personal: 0,
      public: 0,
      unknown: 0
    }
  },
  wifi_setup_steps: [
    "Open router/AP settings and set SSID for your Privacy Guardian LAN.",
    "Select WPA2 or WPA3 mode and set a strong passphrase.",
    "Bind DHCP scope to LAN subnet and reserve IPs for trusted devices.",
    "Set DNS to local resolver (AdGuard on router) and block external DNS bypass.",
    "Save, reboot AP services, then verify internet and DNS leak tests."
  ],
  devices: [],
  stats: {
    dns_queries: 0,
    blocked_queries: 0,
    blocked_percentage: 0,
    time_updated: 0
  }
};

/**
 * Fetch AdGuard stats and transform to dashboard format
 */
async function fetchAdGuardStats() {
  try {
    const url = getApiUrl('stats', 'adguard');
    if (!url) throw new Error('Invalid API URL');

    const response = await fetchWithTimeout(url, {}, CONFIG.timeouts.stats);
    
    if (!response.ok) {
      if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
        console.warn(`AdGuard stats API returned ${response.status}`);
      }
      return null;
    }

    const stats = await response.json();
    
    return {
      dns_queries: stats.dns_queries || 0,
      blocked_queries: stats.blocked_queries || 0,
      blocked_percentage: stats.blocked_percentage || 0,
      time_updated: Math.floor(Date.now() / 1000)
    };
  } catch (err) {
    if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
      console.error('[AdGuard Stats] Failed to fetch:', err.message);
    }
    return null;
  }
}

/**
 * Fetch AdGuard query log
 */
async function fetchAdGuardQueryLog(limit = 100) {
  try {
    const url = CONFIG.api.adguard.baseUrl + '/querylog?limit=' + limit;
    
    const response = await fetchWithTimeout(url, {}, CONFIG.timeouts.querylog);
    
    if (!response.ok) {
      if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
        console.warn(`AdGuard querylog API returned ${response.status}`);
      }
      return [];
    }

    const data = await response.json();
    return data.data || [];
  } catch (err) {
    if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
      console.error('[AdGuard QueryLog] Failed to fetch:', err.message);
    }
    return [];
  }
}

/**
 * Fetch AdGuard top blocked domains
 */
async function fetchTopBlockedDomains(limit = 10) {
  try {
    const url = CONFIG.api.adguard.baseUrl + '/stats/top_blocked_domains?limit=' + limit;
    
    const response = await fetchWithTimeout(url, {}, CONFIG.timeouts.stats);
    
    if (!response.ok) {
      return [];
    }

    const data = await response.json();
    return data || [];
  } catch (err) {
    if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
      console.error('[AdGuard Top Blocked] Failed to fetch:', err.message);
    }
    return [];
  }
}

/**
 * Load data from multiple sources (API first, then fallbacks)
 */
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
      // Merge runtime data with API data (API takes precedence)
      if (runtimeData.devices) {
        data.devices = runtimeData.devices;
      }
      if (runtimeData.dashboard) {
        data.dashboard = { ...data.dashboard, ...runtimeData.dashboard };
      }
      if (runtimeData.stats) {
        data.stats = { ...data.stats, ...runtimeData.stats };
      }
    }
  } catch (err) {
    if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
      console.warn('[runtime.json] Not found or error loading:', err.message);
    }
  }

  // Calculate device counts
  if (data.devices && data.devices.length > 0) {
    const counts = { iot: 0, personal: 0, public: 0, unknown: 0 };
    data.devices.forEach(d => {
      const category = d.category || 'unknown';
      if (category in counts) counts[category]++;
    });
    data.dashboard.counts = { ...counts, total_devices: data.devices.length };
  }

  data.generated_at = new Date().toISOString();
  return data;
}

function card(title, value) {
  return `<article class="card"><p>${title}</p><h3>${value}</h3></article>`;
}

function renderStatusCards(data) {
  const cards = document.getElementById("statusCards");
  const security = data.dashboard.security;
  
  // Format DNS blocked percentage
  const blockedPct = data.stats && data.stats.blocked_percentage 
    ? `${Math.round(data.stats.blocked_percentage * 10) / 10}%` 
    : "N/A";
  
  cards.innerHTML = [
    card("Internet", data.dashboard.internet.up ? "Online" : "Offline"),
    card("WAN IP", data.dashboard.internet.wan_ip || "Unknown"),
    card("Total Devices", data.dashboard.counts.total_devices),
    card("DNS Blocked", blockedPct)
  ].join("");
}

function renderWifiSteps(steps) {
  const list = document.getElementById("wifiSteps");
  list.innerHTML = steps.map((step) => `<li>${step}</li>`).join("");
}

function renderSecurity(data) {
  const securityList = document.getElementById("securityStatus");
  const security = data.dashboard.security;
  const rows = [
    ["Firewall", security.firewall_active ? "Active" : "Inactive"],
    ["DNS Filter", security.adguard_active ? "Active" : "Inactive"],
    ["Wi-Fi AP", security.hostapd_active ? "Active" : "Inactive"],
    ["Mode", security.zone_protection || "Unknown"]
  ];
  securityList.innerHTML = rows.map((row) => `<li><span>${row[0]}</span><strong>${row[1]}</strong></li>`).join("");
}

function renderNetworkMap(data) {
  const map = document.getElementById("networkMap");
  const nodes = data.devices.slice(0, 8).map((d) => {
    return `<div class="map-node"><span>${d.hostname}</span><strong>${d.ip}</strong></div>`;
  });
  map.innerHTML = `<div class="map-node"><span>Gateway</span><strong>${data.dashboard.internet.wan_ip || "WAN"}</strong></div>${nodes.join("")}`;
}

function renderDeviceTable(devices) {
  const tbody = document.getElementById("deviceRows");
  tbody.innerHTML = devices.map((d) => {
    const cls = ["iot", "personal", "public"].includes(d.category) ? d.category : "unknown";
    return `
      <tr>
        <td>${d.ip}</td>
        <td>${d.hostname}</td>
        <td><span class="badge ${cls}">${d.category}</span></td>
        <td>${d.type_hint || "unknown"}</td>
        <td>${d.ssh_reachable ? "Yes" : "No"}</td>
        <td>${d.active_flows ?? 0}</td>
        <td>${Number(d.estimated_bytes || 0).toLocaleString()}</td>
      </tr>
    `;
  }).join("");
}

function renderCategoryTotals(counts) {
  const chips = document.getElementById("categoryTotals");
  const labels = [
    ["IoT", counts.iot],
    ["Personal", counts.personal],
    ["Public", counts.public],
    ["Unknown", counts.unknown]
  ];
  chips.innerHTML = labels.map(([label, value]) => `<span class="chip">${label}: ${value}</span>`).join("");
}

function wireActions() {
  document.getElementById("firmwareUpdate").addEventListener("click", () => {
    document.getElementById("firmwareCommand").textContent = "sudo ./monitor/router-control.sh firmware-update";
  });

  document.querySelectorAll("[data-action]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const action = btn.getAttribute("data-action");
      document.getElementById("toggleCommand").textContent = `sudo ./monitor/router-control.sh ${action}`;
    });
  });

  document.getElementById("saveSettings").addEventListener("click", () => {
    const encryption = document.getElementById("encryption").value;
    const firewallMode = document.getElementById("firewallMode").value;
    const cmd = [
      "sudo ./monitor/router-control.sh set-security",
      `--encryption \"${encryption}\"`,
      `--firewall-mode \"${firewallMode}\"`
    ].join(" ");
    document.getElementById("settingsCommand").textContent = cmd;
  });

  document.getElementById("updateCreds").addEventListener("click", () => {
    const user = document.getElementById("adminUser").value || "routeradmin";
    const pass = document.getElementById("adminPass").value || "<new-password>";
    const cmd = `sudo ./monitor/router-control.sh change-admin --user \"${user}\" --password \"${pass}\"`;
    document.getElementById("credsCommand").textContent = cmd;
  });
}

async function bootstrap() {
  const data = await loadData();
  renderStatusCards(data);
  renderWifiSteps(data.wifi_setup_steps || []);
  renderSecurity(data);
  renderNetworkMap(data);
  renderDeviceTable(data.devices || []);
  renderCategoryTotals(data.dashboard.counts || { iot: 0, personal: 0, public: 0, unknown: 0 });

  document.getElementById("refreshData").addEventListener("click", () => window.location.reload());
}

wireActions();
bootstrap();
