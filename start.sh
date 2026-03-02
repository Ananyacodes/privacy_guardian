#!/bin/bash

echo "Starting Privacy Guardian..."

sudo systemctl start hostapd
sudo systemctl start dnsmasq

sudo bash firewall/apply_firewall.sh

echo "Privacy Guardian running"