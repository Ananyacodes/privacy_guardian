const fallbackData = {
  generated_at: new Date().toISOString(),
  dashboard: {
    internet: { up: true, wan_ip: "10.0.0.28" },
    security: {
      firewall_active: true,
      adguard_active: true,
      hostapd_active: true,
      zone_protection: "strict"
    },
    counts: {
      total_devices: 5,
      iot: 2,
      personal: 2,
      public: 1,
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
  devices: [
    { ip: "192.168.4.12", hostname: "livingroom-tv", category: "iot", type_hint: "TV", ssh_reachable: false, active_flows: 11, estimated_bytes: 343992 },
    { ip: "192.168.4.18", hostname: "kitchen-fridge", category: "iot", type_hint: "Fridge", ssh_reachable: false, active_flows: 4, estimated_bytes: 95120 },
    { ip: "192.168.4.21", hostname: "ananya-phone", category: "personal", type_hint: "Phone", ssh_reachable: false, active_flows: 17, estimated_bytes: 744811 },
    { ip: "192.168.4.27", hostname: "work-laptop", category: "personal", type_hint: "Laptop", ssh_reachable: false, active_flows: 29, estimated_bytes: 1998120 },
    { ip: "192.168.4.40", hostname: "home-server", category: "public", type_hint: "Server", ssh_reachable: true, active_flows: 39, estimated_bytes: 6542109 }
  ]
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

function card(title, value) {
  return `<article class="card"><p>${title}</p><h3>${value}</h3></article>`;
}

function renderStatusCards(data) {
  const cards = document.getElementById("statusCards");
  const security = data.dashboard.security;
  cards.innerHTML = [
    card("Internet", data.dashboard.internet.up ? "Online" : "Offline"),
    card("WAN IP", data.dashboard.internet.wan_ip || "Unknown"),
    card("Total Devices", data.dashboard.counts.total_devices),
    card("Protection", security.zone_protection || "Unknown")
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
