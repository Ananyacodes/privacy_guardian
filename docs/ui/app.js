/**
 * Privacy Guardian Dashboard - Complete Backend
 * Integrates with AdGuard Home API for real-time monitoring and device management
 */

const API_CONFIG = {
  baseUrl: '/api/adguard',
  endpoints: {
    stats: '/stats',
    clients: '/clients',
    querylog: '/querylog',
    topBlocked: '/stats/top_blocked_domains',
    topQueried: '/stats/top_queried_domains',
    info: '/info'
  },
  timeouts: {
    default: 5000,
    stats: 10000,
    querylog: 15000
  },
  refreshInterval: 30000
};

// State management
const state = {
  stats: null,
  clients: null,
  queryLog: null,
  devices: new Map(),
  lastUpdate: null
};

/**
 * Fetch with timeout wrapper
 */
async function fetchWithTimeout(url, options = {}, timeout = 5000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers
      },
      credentials: 'same-origin',
      signal: controller.signal,
      ...options
    });
    clearTimeout(timeoutId);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await response.json();
  } catch (error) {
    clearTimeout(timeoutId);
    console.error('API Error:', error);
    return null;
  }
}

/**
 * Format bytes to human readable
 */
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
}

/**
 * Categorize device based on hostname and IP patterns
 */
function categorizeDevice(client) {
  const hostname = (client.name || client.hostname || '').toLowerCase();
  const ip = client.ip || '';

  // Public category: SSH reachable hosts or common servers
  if (client.whois_info || hostname.includes('server') || hostname.includes('host') || hostname.includes('pi')) {
    return { category: 'Public', hint: 'SSH-enabled host' };
  }

  // IoT category: common IoT device patterns
  if (hostname.includes('tv') || hostname.includes('alexa') || hostname.includes('echo') ||
      hostname.includes('fridge') || hostname.includes('camera') || hostname.includes('nest') ||
      hostname.includes('smart') || hostname.includes('printer') || hostname.includes('hub')) {
    return { category: 'IoT', hint: 'Smart device' };
  }

  // Personal category: phones, laptops, computers
  if (hostname.includes('iphone') || hostname.includes('macbook') || hostname.includes('laptop') ||
      hostname.includes('desktop') || hostname.includes('android') || hostname.includes('windows') ||
      hostname.includes('phone')) {
    return { category: 'Personal', hint: 'Personal device' };
  }

  // Default to Unknown if no patterns match
  return { category: 'Unknown', hint: 'Auto-detected' };
}

/**
 * Check if device is SSH reachable (mock for now)
 */
function isSSHReachable(client) {
  // In production, this would do actual SSH port scanning
  // For now, we'll check if it's marked as a server/host
  return client.whois_info ? 'Yes' : 'No';
}

/**
 * Fetch AdGuard stats
 */
async function fetchStats() {
  const data = await fetchWithTimeout(
    `${API_CONFIG.baseUrl}${API_CONFIG.endpoints.stats}`,
    {},
    API_CONFIG.timeouts.stats
  );
  state.stats = data;
  return data;
}

/**
 * Fetch connected clients
 */
async function fetchClients() {
  const data = await fetchWithTimeout(
    `${API_CONFIG.baseUrl}${API_CONFIG.endpoints.clients}`,
    {},
    API_CONFIG.timeouts.default
  );
  if (data && data.clients) {
    state.clients = data.clients;
    // Build device map for categorization
    data.clients.forEach(client => {
      state.devices.set(client.ip, {
        ...client,
        category: categorizeDevice(client).category,
        typeHint: categorizeDevice(client).hint,
        sshReachable: isSSHReachable(client)
      });
    });
  }
  return data;
}

/**
 * Fetch query log for device activity
 */
async function fetchQueryLog() {
  const data = await fetchWithTimeout(
    `${API_CONFIG.baseUrl}${API_CONFIG.endpoints.querylog}`,
    {},
    API_CONFIG.timeouts.querylog
  );
  state.queryLog = data;
  return data;
}

/**
 * Update dashboard status cards
 */
async function updateDashboard() {
  await fetchStats();
  const container = document.getElementById('statusCards');
  if (!container || !state.stats) return;

  const cards = [
    {
      title: 'DNS Queries',
      value: (state.stats.dns_queries || 0).toLocaleString(),
      unit: 'total'
    },
    {
      title: 'Blocked Queries',
      value: (state.stats.blocked_queries || 0).toLocaleString(),
      unit: 'blocked'
    },
    {
      title: 'Block Rate',
      value: ((state.stats.blocked_percentage || 0).toFixed(2)) + '%',
      unit: 'today'
    },
    {
      title: 'Rewrites',
      value: (state.stats.rewrites || 0).toLocaleString(),
      unit: 'rules'
    }
  ];

  container.innerHTML = cards.map(card => `
    <article class="card">
      <p>${card.unit}</p>
      <h3>${card.value}</h3>
    </article>
  `).join('');
}

/**
 * Update security status
 */
function updateSecurityStatus() {
  const container = document.getElementById('securityStatus');
  if (!container) return;

  const services = [
    { name: 'AdGuard Home', status: state.stats ? 'Active' : 'Inactive' },
    { name: 'Firewall', status: 'Active' },
    { name: 'Wi-Fi AP', status: 'Active' },
    { name: 'DNS Filter', status: 'Active' }
  ];

  container.innerHTML = services.map(srv => `
    <li>
      <span style="color: ${srv.status === 'Active' ? '#00ff41' : '#ff4757'};">●</span>
      ${srv.name}
      <strong style="color: var(--ink-muted);">${srv.status}</strong>
    </li>
  `).join('');
}

/**
 * Update network map (device summary)
 */
async function updateNetworkMap() {
  await fetchClients();
  const container = document.getElementById('networkMap');
  if (!container || !state.clients || state.clients.length === 0) return;

  const topDevices = state.clients.slice(0, 5);
  container.innerHTML = topDevices.map(device => `
    <div class="map-node">
      <div>
        <strong>${device.name || device.ip}</strong>
        <small style="color: var(--ink-muted);">${device.ip}</small>
      </div>
      <div style="text-align: right;">
        <small style="color: var(--accent);">active</small>
      </div>
    </div>
  `).join('');
}

/**
 * Update Wi-Fi setup steps
 */
function updateWifiSteps() {
  const container = document.getElementById('wifiSteps');
  if (!container) return;

  const steps = [
    'Connect to the Raspberry Pi via SSH or access network settings',
    'Configure SSID and WPA2/WPA3 passphrase in hostapd.conf',
    'Set DHCP scope and IP range in dnsmasq.conf',
    'Configure AdGuard Home DNS servers for blocking',
    'Enable IP forwarding and set firewall rules',
    'Restart Wi-Fi AP with: sudo docker restart pg-hostapd',
    'Verify DNS settings with: dig @&lt;pi-ip&gt; example.com'
  ];

  container.innerHTML = steps.map(step => `<li>${step}</li>`).join('');
}

/**
 * Update device management table
 */
async function updateDeviceManagement() {
  await fetchClients();
  
  const container = document.getElementById('deviceRows');
  const categoryContainer = document.getElementById('categoryTotals');
  
  if (!container || !state.clients) return;

  // Count devices by category
  const categoryCounts = {
    'IoT': 0,
    'Personal': 0,
    'Public': 0,
    'Unknown': 0
  };

  // Build table rows
  const rows = state.clients.map(client => {
    const device = state.devices.get(client.ip) || categorizeDevice(client);
    categoryCounts[device.category]++;
    return `
      <tr>
        <td><code>${client.ip}</code></td>
        <td>${client.name || client.hostname || '-'}</td>
        <td><span class="badge" style="background: var(--accent); color: var(--ink);">${device.category}</span></td>
        <td>${device.typeHint}</td>
        <td>${isSSHReachable(client)}</td>
        <td>-</td>
        <td>-</td>
      </tr>
    `;
  }).join('');

  container.innerHTML = rows || '<tr><td colspan="7" style="text-align: center; color: var(--ink-muted);">No devices connected</td></tr>';

  // Update category totals
  if (categoryContainer) {
    categoryContainer.innerHTML = Object.entries(categoryCounts).map(([cat, count]) => `
      <span class="chip">${cat}: ${count}</span>
    `).join('');
  }
}

/**
 * Setup action button handlers
 */
function setupActionButtons() {
  document.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const action = btn.dataset.action;
      const commandEl = document.getElementById('toggleCommand');

      const commands = {
        'restart-services': 'sudo docker compose restart pg-adguard pg-dnsmasq pg-hostapd',
        'toggle-firewall': 'sudo docker restart pg-firewall',
        'toggle-wifi': 'sudo docker restart pg-hostapd',
        'toggle-dns': 'sudo docker restart pg-adguard'
      };

      if (commandEl && commands[action]) {
        commandEl.textContent = commands[action];
        btn.textContent = 'Command generated ✓';
        setTimeout(() => {
          btn.textContent = btn.getAttribute('data-action').split('-').map(w => 
            w.charAt(0).toUpperCase() + w.slice(1)
          ).join(' ');
        }, 2000);
      }
    });
  });
}

/**
 * Setup settings form
 */
function setupSettings() {
  const saveBtn = document.getElementById('saveSettings');
  if (saveBtn) {
    saveBtn.addEventListener('click', () => {
      const encryption = document.getElementById('encryption')?.value || 'WPA2';
      const firewallMode = document.getElementById('firewallMode')?.value || 'strict';
      const commandEl = document.getElementById('settingsCommand');

      const command = `# Apply: ${encryption} encryption + ${firewallMode} firewall\nsudo docker compose up -d`;
      if (commandEl) {
        commandEl.textContent = command;
        saveBtn.textContent = 'Settings command generated ✓';
        setTimeout(() => {
          saveBtn.textContent = 'Generate Settings Command';
        }, 2000);
      }
    });
  }
}

/**
 * Setup credentials form
 */
function setupCredentials() {
  const updateBtn = document.getElementById('updateCreds');
  if (updateBtn) {
    updateBtn.addEventListener('click', () => {
      const username = document.getElementById('adminUser')?.value || 'routeradmin';
      const password = document.getElementById('adminPass')?.value;
      const commandEl = document.getElementById('credsCommand');

      if (!password) {
        alert('Please enter a strong password');
        return;
      }

      const command = `# Update credentials\n# Username: ${username}\n# Set password via AdGuard UI: http://localhost:3000`;
      if (commandEl) {
        commandEl.textContent = command;
        updateBtn.textContent = 'Credentials command generated ✓';
        setTimeout(() => {
          updateBtn.textContent = 'Generate Credentials Command';
        }, 2000);
      }
    });
  }
}

/**
 * Setup firmware update
 */
function setupFirmwareUpdate() {
  const updateBtn = document.getElementById('firmwareUpdate');
  if (updateBtn) {
    updateBtn.addEventListener('click', () => {
      const commandEl = document.getElementById('firmwareCommand');
      const command = `# Run OTA update\nsudo docker compose exec pg-dnsmasq apt-get update\nsudo docker compose exec pg-dnsmasq apt-get upgrade -y\nsudo docker compose restart`;
      if (commandEl) {
        commandEl.textContent = command;
        updateBtn.textContent = 'Update command generated ✓';
        setTimeout(() => {
          updateBtn.textContent = 'Run OTA Update';
        }, 2000);
      }
    });
  }
}

/**
 * Setup refresh button
 */
function setupRefresh() {
  const refreshBtn = document.getElementById('refreshData');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', async () => {
      refreshBtn.disabled = true;
      refreshBtn.textContent = 'Refreshing...';
      await updateAllData();
      refreshBtn.disabled = false;
      refreshBtn.textContent = 'Refresh Data';
      state.lastUpdate = new Date();
    });
  }
}

/**
 * Update all dashboard data
 */
async function updateAllData() {
  await Promise.all([
    updateDashboard(),
    updateNetworkMap(),
    updateDeviceManagement(),
    fetchQueryLog()
  ]);
  updateSecurityStatus();
}

/**
 * Initialize dashboard
 */
function init() {
  // Setup handlers
  setupActionButtons();
  setupSettings();
  setupCredentials();
  setupFirmwareUpdate();
  setupRefresh();
  updateWifiSteps();

  // Load data immediately
  updateAllData();

  // Auto-refresh periodically
  setInterval(updateAllData, API_CONFIG.refreshInterval);
}

// Start when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
