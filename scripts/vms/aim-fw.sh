#!/bin/bash
# Source allow-list for the aim KG (tcp 18282) and the Syncthing hub (tcp+udp 22000) on
# 192.168.100.100. Idempotent; run by aim-fw.service after docker.service.
# Allowed: 192.168.100.104 (LXC 104 WireGuard masquerade: every 10.8.0.0/24 peer and LXC 104
# itself) and 192.168.2.245 (macbook, UCG DHCP reservation). Every other source is rejected.
# NetBird cutover changes the WireGuard source: update ALLOW then.
set -eu
ALLOW="192.168.100.104 192.168.2.245"
HUB=192.168.100.100

iptables -N AIM-FW 2>/dev/null || true
iptables -F AIM-FW
for src in $ALLOW; do iptables -A AIM-FW -s "$src" -j RETURN; done
iptables -A AIM-FW -p tcp -j REJECT --reject-with tcp-reset
iptables -A AIM-FW -j REJECT

for rule in "tcp 18282" "tcp 22000" "udp 22000"; do
  set -- $rule
  m=(-p "$1" -m conntrack --ctdir ORIGINAL --ctorigdst "$HUB" --ctorigdstport "$2" -j AIM-FW)
  iptables -C DOCKER-USER "${m[@]}" 2>/dev/null || iptables -I DOCKER-USER "${m[@]}"
done
