/**
 * Privacy Guardian Frontend Configuration
 * API endpoint configuration for all backend services
 * 
 * Within Docker:
 * - AdGuard API: http://pg-adguard:3000 (internal)
 *   Accessed via proxy: /api/adguard/
 * 
 * From network:
 * - Replace <pi-ip> with your Raspberry Pi IP address
 * - UI port: 8080
 * - AdGuard direct: 3000 (if port forwarded)
 */

const CONFIG = {
  // ─────────────────────────────────────────────────────────────────────
  // API Endpoints
  // ─────────────────────────────────────────────────────────────────────
  
  // AdGuard Home API endpoints (via local proxy)
  api: {
    adguard: {
      // Base URL for AdGuard proxy (local)
      baseUrl: '/api/adguard',
      
      // Stats endpoint
      stats: '/api/adguard/stats',
      
      // Query log
      querylog: '/api/adguard/querylog',
      
      // Top blocked domains
      topBlocked: '/api/adguard/stats/top_blocked_domains',
      
      // Top queried domains
      topQueried: '/api/adguard/stats/top_queried_domains',
      
      // Connected clients
      clients: '/api/adguard/clients',
      
      // AdGuard info
      info: '/api/adguard/info',
      
      // AdGuard version
      version: '/api/adguard/version'
    },
    
    // Router API (for future use)
    router: {
      baseUrl: '/api/router',
      devices: '/api/router/devices',
      network: '/api/router/network',
      firewall: '/api/router/firewall'
    }
  },

  // ─────────────────────────────────────────────────────────────────────
  // Fetch Options
  // ─────────────────────────────────────────────────────────────────────
  
  fetchOptions: {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    credentials: 'same-origin'
  },

  // ─────────────────────────────────────────────────────────────────────
  // Timeouts
  // ─────────────────────────────────────────────────────────────────────
  
  timeouts: {
    default: 5000,      // 5 seconds
    stats: 10000,       // 10 seconds
    querylog: 15000     // 15 seconds
  },

  // ─────────────────────────────────────────────────────────────────────
  // Cache Configuration
  // ─────────────────────────────────────────────────────────────────────
  
  cache: {
    // Cache duration in milliseconds
    duration: 30000,     // 30 seconds
    
    // Keys for local cache
    keys: {
      stats: 'pg_stats_cache',
      querylog: 'pg_querylog_cache',
      clients: 'pg_clients_cache'
    }
  },

  // ─────────────────────────────────────────────────────────────────────
  // Debug Mode
  // ─────────────────────────────────────────────────────────────────────
  debug: {
    enabled: true,
    logApiCalls: true,
    logErrors: true
  }
};

/**
 * Helper function to get full API URL
 * @param {string} endpoint - The endpoint (e.g., 'stats')
 * @param {string} service - The service (e.g., 'adguard')
 * @returns {string} Full API URL
 */
function getApiUrl(endpoint, service = 'adguard') {
  const serviceConfig = CONFIG.api[service];
  if (!serviceConfig) {
    console.error(`Unknown service: ${service}`);
    return null;
  }
  return serviceConfig[endpoint] || null;
}

/**
 * Helper function to fetch with timeout
 * @param {string} url - The URL to fetch
 * @param {object} options - Fetch options
 * @param {number} timeout - Timeout in ms
 * @returns {Promise} Fetch promise
 */
async function fetchWithTimeout(url, options = {}, timeout = CONFIG.timeouts.default) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      ...CONFIG.fetchOptions,
      ...options,
      signal: controller.signal
    });

    if (CONFIG.debug.enabled && CONFIG.debug.logApiCalls) {
      console.log(`[API] ${url} - Status: ${response.status}`);
    }

    return response;
  } catch (error) {
    if (CONFIG.debug.enabled && CONFIG.debug.logErrors) {
      console.error(`[API Error] ${url}:`, error.message);
    }
    throw error;
  } finally {
    clearTimeout(id);
  }
}

/**
 * Simple cache getter/setter
 * @param {string} key - Cache key
 * @param {function} fetcher - Function to fetch data if not cached
 * @returns {Promise} Cached or fetched data
 */
async function getCachedData(key, fetcher) {
  const cacheKey = key;
  const cached = localStorage.getItem(cacheKey);
  
  if (cached) {
    const data = JSON.parse(cached);
    if (Date.now() - data.timestamp < CONFIG.cache.duration) {
      return data.value;
    }
  }

  const value = await fetcher();
  localStorage.setItem(cacheKey, JSON.stringify({
    value,
    timestamp: Date.now()
  }));

  return value;
}
