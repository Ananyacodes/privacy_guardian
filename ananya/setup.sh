#!/bin/bash

echo "Setting up Privacy Guardian..."

cp config/hostapd.conf /etc/hostapd/hostapd.conf
cp config/dnsmasq.conf /etc/dnsmasq.conf

systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq

sysctl -w net.ipv4.ip_forward=1

echo "Setup complete"