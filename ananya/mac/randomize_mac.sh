#!/bin/bash

interface="eth0"

ip link set $interface down
macchanger -r $interface
ip link set $interface up