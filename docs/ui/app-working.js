/**
 * Privacy Guardian Dashboard - Working Version
 * Fully functional frontend with AdGuard Home API integration
 */

const CONFIG = {
  api: {
    adguard: {
      stats: '/api/adguard/stats',
      querylog: '/api/adguard/querylog',
      topBlocked: '/api/adguard/stats/top_blocked_domains',
      topQueried: '/api/adguard/stats/top_queried_domains',
      clients: '/api/adguard/clients',
      info: '/api/adguard/info'
    }
  },
  timeouts: {
    stats: 10000,
    querylog: 15000
  },
  refreshInterval: 30000 // 30 seconds
};

// State management
const state = {
  stats: null,
  clients: null,
  lastUpdate: null
};

/**
 * Fetch with timeout wrapper
 */
async function fetchWithTimeout(url, options = {}, timeout = 10000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...options.headers
      }
    });
    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    throw error;
  }
}

/**
 * Format bytes to human readable
 */
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}

/**
 * Format percentage
 */
function formatPercent(value) {
  return Math.round(value * 100) / 100 + '%';
}

/**
 * Fetch AdGuard stats
 */
async function fetchStats() {
  try {
    const response = await fetchWithTimeout(CONFIG.api.adguard.stats, {}, CONFIG.timeouts.stats);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    state.stats = data;
    state.lastUpdate = new Date();
    return data;
  } catch (error) {
    console.error('Error fetching stats:', error);
    return null;
  }
}

/**
 * Update dashboard cards
 */
async function updateDashboard() {
  const stats = await fetchStats();
  const container = document.getElementById('statusCards');
  
  if (!container) return;

  if (!stats) {
    container.innerHTML = '<div class="card error"><p>Unable to load stats</p></div>';
    return;
  }

  const cards = [
    {
      title: 'DNS Queries',
      value: (stats.dns_queries || 0).toLocaleString(),
      subtitle: 'total queries'
    },
    {
      title: 'Blocked Queries',
      value: (stats.blocked_queries || 0).toLocaleString(),
      subtitle: 'blocked by filters'
    },
    {
      title: 'Block Rate',
      value: formatPercent(stats.blocked_percentage || 0),
      subtitle: 'of all queries'
    },
    {
      title: 'DNS Rewrites',
      value: (stats.rewrites || 0).toLocaleString(),
      subtitle: 'custom rules'
    }
  ];

  container.innerHTML = cards.map(card => `
    <div class="card">
      <p>${card.subtitle}</p>
      <h3>${card.value}</h3>
      <p style="font-size: 0.9rem; color: var(--accent);">${card.title}</p>
    </div>
  `).join('');
}

/**
 * Update top blocked domains
 */
async function updateTopBlocked() {
  try {
    const response = await fetchWithTimeout(CONFIG.api.adguard.topBlocked, {}, CONFIG.timeouts.stats);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    
    const container = document.getElementById('topBlockedList');
    if (!container) return;

    if (!data || data.length === 0) {
      container.innerHTML = '<p style="color: var(--ink-muted);">No blocked domains yet</p>';
      return;
    }

    container.innerHTML = data.slice(0, 10).map((item, idx) => `
      <li style="padding: 0.5rem 0; border-bottom: 1px solid var(--line);">
        <strong>${idx + 1}.</strong> ${item}
      </li>
    `).join('');
  } catch (error) {
    console.error('Error fetching top blocked:', error);
  }
}

/**
 * Update connected clients
 */
async function updateClients() {
  try {
    const response = await fetchWithTimeout(CONFIG.api.adguard.clients, {}, CONFIG.timeouts.stats);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    
    const container = document.getElementById('clientsList');
    if (!container) return;

    const clients = data.clients || [];
    if (clients.length === 0) {
      container.innerHTML = '<p style="color: var(--ink-muted);">No clients connected</p>';
      return;
    }

    container.innerHTML = clients.slice(0, 10).map(client => `
      <li style="padding: 0.5rem 0; border-bottom: 1px solid var(--line);">
        <strong>${client.name || client.ip}</strong><br>
        <small style="color: var(--ink-muted);">${client.ip}</small>
      </li>
    `).join('');
  } catch (error) {
    console.error('Error fetching clients:', error);
  }
}

/**
 * Setup action buttons
 */
function setupActionButtons() {
  const actionButtons = document.querySelectorAll('[data-action]');
  
  actionButtons.forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.preventDefault();
      const action = btn.dataset.action;
      const commandEl = document.getElementById('toggleCommand');
      
      const commands = {
        'restart-services': 'sudo docker compose restart pg-adguard pg-dnsmasq pg-hostapd',
        'toggle-firewall': 'sudo docker exec pg-firewall nft flush ruleset',
        'toggle-wifi': 'sudo docker exec pg-hostapd hostapd_cli quit',
        'toggle-dns': 'sudo docker restart pg-adguard'
      };

      if (commandEl) {
        commandEl.textContent = commands[action] || 'Command not found';
      }
      
      btn.textContent = 'Command generated ✓';
      setTimeout(() => {
        btn.textContent = btn.getAttribute('data-action').split('-').join(' ').toUpperCase();
      }, 2000);
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
      
      const command = `# Apply settings: ${encryption} encryption + ${firewallMode} firewall\nsudo docker compose up -d`;
      if (commandEl) commandEl.textContent = command;
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
        alert('Please enter a password');
        return;
      }
      
      const command = `# Update admin credentials\n# Username: ${username}\n# Password: (set via AdGuard UI at http://localhost:3000)`;
      if (commandEl) commandEl.textContent = command;
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
      const command = `# Run OTA update\nsudo docker compose exec pg-dnsmasq apt-get update && apt-get upgrade -y\nsudo docker compose restart`;
      if (commandEl) commandEl.textContent = command;
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
      await updateAllData();
      refreshBtn.disabled = false;
    });
  }
}

/**
 * Update all dashboard data
 */
async function updateAllData() {
  await Promise.all([
    updateDashboard(),
    updateTopBlocked(),
    updateClients()
  ]);
}

/**
 * Initialize dashboard
 */
function init() {
  setupActionButtons();
  setupSettings();
  setupCredentials();
  setupFirmwareUpdate();
  setupRefresh();
  
  // Load data immediately
  updateAllData();
  
  // Auto-refresh data periodically
  setInterval(updateAllData, CONFIG.refreshInterval);
}

// Start when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
