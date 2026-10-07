#!/bin/bash
# Watch the Navigabene IPv6 delegated prefix (ticket VYU-510137). Every minute LXC 108 pings two
# public IPv6 hosts from its SLAAC address in 2a0d:b287:dc20:5900::/64 (a LAN client path through
# the UCG). IPv6 is bad when neither host answers. IPv4 from winston is checked too, so a full
# line outage is not reported as an IPv6 fault. Each bad check goes to LOG with a timestamp (the
# evidence for the ticket); a state change (ok -> bad, bad -> ok) posts to the nwlab ntfy.
set -u
CT=108
TARGETS="2606:4700:4700::1111 2001:4860:4860::8888"
TOPIC=https://ntfy.nwlab.nwdesigns.it/homelab-alerts
STATE=/var/lib/ipv6-pd-watch.state
LOG=/var/log/ipv6-pd-watch.log

v6=bad
for t in $TARGETS; do
  pct exec "$CT" -- ping -6 -c 3 -W 2 -q "$t" >/dev/null 2>&1 && { v6=ok; break; }
done
v4=ok
ping -c 3 -W 2 -q 1.1.1.1 >/dev/null 2>&1 || v4=bad
src=$(pct exec "$CT" -- ip -6 -o addr show scope global 2>/dev/null | awk '/2a0d:/{print $4; exit}')

if [ "$v6" = ok ]; then
  state=ok; msg="IPv6 OK again from ${src:-?}"
elif [ "$v4" = bad ]; then
  state=down; msg="line down: no IPv4 and no IPv6"
else
  state=bad; msg="IPv6 down from ${src:-no 2a0d address} (IPv4 OK)"
fi

[ "$state" != ok ] && echo "$(date -Is) $state $msg" >> "$LOG"
prev=$(cat "$STATE" 2>/dev/null || echo ok)
[ "$state" = "$prev" ] && exit 0
echo "$(date -Is) change $prev -> $state: $msg" >> "$LOG"
if [ "$state" = ok ]; then
  curl -fsS -m 10 -H "Title: home IPv6 (Navigabene)" -H "Tags: white_check_mark" \
    -d "$msg" "$TOPIC" >/dev/null || exit 1
else
  curl -fsS -m 10 -H "Title: home IPv6 (Navigabene)" -H "Priority: high" -H "Tags: rotating_light" \
    -d "$msg" "$TOPIC" >/dev/null || exit 1
fi
echo "$state" > "$STATE"
