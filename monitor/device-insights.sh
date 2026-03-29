#!/bin/bash
# device-insights.sh
# Builds a runtime JSON snapshot for the UI with device categorization and usage hints.

set -euo pipefail

LEASES_FILE="/var/lib/misc/dnsmasq.leases"
OUT_FILE="${1:-./docs/ui/data/runtime.json}"

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/ }"
    printf '%s' "$s"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

internet_up=false
wan_ip=""
if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    internet_up=true
fi
wan_ip="$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | head -n 1 | cut -d/ -f1)"

firewall_active=false
adguard_active=false
hostapd_active=false
if systemctl is-active --quiet nftables 2>/dev/null; then firewall_active=true; fi
if systemctl is-active --quiet AdGuardHome 2>/dev/null; then adguard_active=true; fi
if systemctl is-active --quiet hostapd 2>/dev/null; then hostapd_active=true; fi

count_iot=0
count_personal=0
count_public=0
count_unknown=0
total_devices=0

devices_json=""
first=true

infer_type_hint() {
    local host="$1"
    local lower
    lower="$(echo "$host" | tr '[:upper:]' '[:lower:]')"

    if echo "$lower" | grep -Eq 'tv|fridge|camera|cam|iot|thermostat|speaker|plug|bulb'; then
        echo "IoT Appliance"
    elif echo "$lower" | grep -Eq 'laptop|phone|iphone|android|pixel|ipad|macbook'; then
        echo "Personal Device"
    elif echo "$lower" | grep -Eq 'server|nas|desktop|workstation|pc'; then
        echo "Shared Computer"
    else
        echo "Unknown"
    fi
}

ssh_reachable() {
    local ip="$1"
    if timeout 1 bash -c "</dev/tcp/$ip/22" >/dev/null 2>&1; then
        echo true
    else
        echo false
    fi
}

estimate_usage() {
    local ip="$1"
    local flows=0
    local bytes=0

    if [ -r /proc/net/nf_conntrack ]; then
        read -r flows bytes <<EOF
$(awk -v ip="$ip" '
$0 ~ ("src=" ip) {
    c++
    if (match($0, /bytes=([0-9]+)/, m)) b += m[1]
}
END {
    printf "%d %d\n", c, b
}
' /proc/net/nf_conntrack)
EOF
    fi

    echo "$flows $bytes"
}

categorize_device() {
    local hostname="$1"
    local ssh="$2"
    local lower
    lower="$(echo "$hostname" | tr '[:upper:]' '[:lower:]')"

    if [ "$ssh" = "true" ]; then
        echo "public"
    elif echo "$lower" | grep -Eq 'tv|fridge|camera|cam|iot|thermostat|speaker|plug|bulb'; then
        echo "iot"
    elif echo "$lower" | grep -Eq 'laptop|phone|iphone|android|pixel|ipad|macbook'; then
        echo "personal"
    elif echo "$lower" | grep -Eq 'server|nas|desktop|workstation|pc'; then
        echo "public"
    else
        echo "unknown"
    fi
}

if [ -f "$LEASES_FILE" ]; then
    while IFS=' ' read -r expiry mac ip hostname clientid; do
        [ -n "${ip:-}" ] || continue
        [ -n "${hostname:-}" ] || hostname="unknown"

        ssh="$(ssh_reachable "$ip")"
        category="$(categorize_device "$hostname" "$ssh")"
        type_hint="$(infer_type_hint "$hostname")"

        read -r flows bytes <<< "$(estimate_usage "$ip")"

        case "$category" in
            iot) count_iot=$((count_iot + 1)) ;;
            personal) count_personal=$((count_personal + 1)) ;;
            public) count_public=$((count_public + 1)) ;;
            *) count_unknown=$((count_unknown + 1)) ;;
        esac
        total_devices=$((total_devices + 1))

        [ "$first" = true ] || devices_json+=$',\n'
        first=false

        esc_host="$(json_escape "$hostname")"
        esc_type="$(json_escape "$type_hint")"

        devices_json+="    {\n"
        devices_json+="      \"ip\": \"$ip\",\n"
        devices_json+="      \"hostname\": \"$esc_host\",\n"
        devices_json+="      \"category\": \"$category\",\n"
        devices_json+="      \"type_hint\": \"$esc_type\",\n"
        devices_json+="      \"ssh_reachable\": $ssh,\n"
        devices_json+="      \"active_flows\": $flows,\n"
        devices_json+="      \"estimated_bytes\": $bytes\n"
        devices_json+="    }"
    done < "$LEASES_FILE"
fi

mkdir -p "$(dirname "$OUT_FILE")"

cat > "$OUT_FILE" <<EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dashboard": {
    "internet": {
      "up": $internet_up,
      "wan_ip": "${wan_ip:-unknown}"
    },
    "security": {
      "firewall_active": $firewall_active,
      "adguard_active": $adguard_active,
      "hostapd_active": $hostapd_active,
      "zone_protection": "strict"
    },
    "counts": {
      "total_devices": $total_devices,
      "iot": $count_iot,
      "personal": $count_personal,
      "public": $count_public,
      "unknown": $count_unknown
    }
  },
  "wifi_setup_steps": [
    "Open router/AP settings and set SSID for your Privacy Guardian LAN.",
    "Select WPA2 or WPA3 mode and set a strong passphrase.",
    "Bind DHCP scope to LAN subnet and reserve IPs for trusted devices.",
    "Set DNS to local resolver (AdGuard on router) and block external DNS bypass.",
    "Save, reboot AP services, then verify internet and DNS leak tests."
  ],
  "devices": [
$devices_json
  ]
}
EOF

echo "Wrote runtime data to: $OUT_FILE"
