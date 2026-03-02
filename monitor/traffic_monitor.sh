#!/bin/bash

echo "Monitoring traffic..."

while true
do
    ip -s link show wlan0
    sleep 5
done