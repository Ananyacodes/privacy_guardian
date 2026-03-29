#!/bin/bash
# router-control.sh
# Basic action script for UI-triggered router operations.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  sudo ./monitor/router-control.sh status
  sudo ./monitor/router-control.sh firmware-update
  sudo ./monitor/router-control.sh restart-services
  sudo ./monitor/router-control.sh toggle-firewall [on|off]
  sudo ./monitor/router-control.sh toggle-wifi [on|off]
  sudo ./monitor/router-control.sh toggle-dns [on|off]
  sudo ./monitor/router-control.sh set-security --encryption <WPA2|WPA3|WPA2/WPA3 Mixed> --firewall-mode <strict|balanced|custom>
  sudo ./monitor/router-control.sh change-admin --user <name> --password <password>
EOF
}

service_state() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "on"
    else
        echo "off"
    fi
}

toggle_service() {
    local svc="$1"
    local desired="${2:-}"
    local current
    current="$(service_state "$svc")"

    if [ -z "$desired" ]; then
        if [ "$current" = "on" ]; then
            desired="off"
        else
            desired="on"
        fi
    fi

    case "$desired" in
        on)
            systemctl start "$svc"
            echo "$svc => on"
            ;;
        off)
            systemctl stop "$svc"
            echo "$svc => off"
            ;;
        *)
            echo "Invalid toggle state: $desired"
            exit 1
            ;;
    esac
}

command="${1:-}"
shift || true

case "$command" in
status)
    echo "nftables: $(service_state nftables)"
    echo "hostapd: $(service_state hostapd)"
    echo "AdGuardHome: $(service_state AdGuardHome)"
    ;;

firmware-update)
    echo "Running OTA package refresh..."
    apt-get update -qq
    apt-get upgrade -y
    echo "OTA update complete"
    ;;

restart-services)
    systemctl restart hostapd dnsmasq AdGuardHome nftables
    echo "Core services restarted"
    ;;

toggle-firewall)
    toggle_service nftables "${1:-}"
    ;;

toggle-wifi)
    toggle_service hostapd "${1:-}"
    ;;

toggle-dns)
    toggle_service AdGuardHome "${1:-}"
    ;;

set-security)
    encryption=""
    fw_mode=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --encryption)
                encryption="${2:-}"
                shift 2
                ;;
            --firewall-mode)
                fw_mode="${2:-}"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    [ -n "$encryption" ] || { echo "Missing --encryption"; exit 1; }
    [ -n "$fw_mode" ] || { echo "Missing --firewall-mode"; exit 1; }

    echo "Requested encryption mode: $encryption"
    echo "Requested firewall mode: $fw_mode"
    echo "Apply encryption by updating hostapd.conf and reload hostapd."
    echo "Apply firewall profile by swapping nftables template and running pg-manage.sh reload."
    ;;

change-admin)
    admin_user=""
    admin_pass=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --user)
                admin_user="${2:-}"
                shift 2
                ;;
            --password)
                admin_pass="${2:-}"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    [ -n "$admin_user" ] || { echo "Missing --user"; exit 1; }
    [ -n "$admin_pass" ] || { echo "Missing --password"; exit 1; }

    if id "$admin_user" >/dev/null 2>&1; then
        echo "$admin_user:$admin_pass" | chpasswd
        echo "Password updated for existing admin user: $admin_user"
    else
        useradd -m -s /bin/bash "$admin_user"
        echo "$admin_user:$admin_pass" | chpasswd
        usermod -aG sudo "$admin_user"
        echo "Created admin user and granted sudo: $admin_user"
    fi
    ;;

help|""|*)
    usage
    ;;
esac
