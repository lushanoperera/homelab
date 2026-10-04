#!/bin/bash
# Stale/failed alert for the aim KG history job on Flatcar VM 100 (aim-history.service).
# Reads the unit through the QEMU guest agent and posts to the nwlab ntfy on a state change
# (ok -> bad, bad -> ok). Bad = Result is not success, the last successful run is older than
# MAX_AGE, or the guest agent does not answer. A clean-tree run exits 0 and counts as success.
set -u
VMID=100
MAX_AGE=7200
TOPIC=https://ntfy.nwlab.nwdesigns.it/homelab-alerts
STATE=/var/lib/aim-history-watch.state

out=$(qm guest exec "$VMID" --timeout 15 -- systemctl show aim-history.service \
  -p Result -p ExecMainExitTimestamp --timestamp=unix 2>&1 | jq -r '."out-data" // empty' 2>/dev/null)
result=$(sed -n 's/^Result=//p' <<<"$out")
ts=$(sed -n 's/^ExecMainExitTimestamp=@//p' <<<"$out")
age=$(( $(date +%s) - ${ts:-0} ))

if [ -z "$result" ]; then
  state=bad; msg="cannot read aim-history.service on VM $VMID (guest agent did not answer)"
elif [ "$result" != success ]; then
  state=bad; msg="aim-history.service on VM $VMID failed (Result=$result)"
elif [ -z "$ts" ] || [ "$age" -gt "$MAX_AGE" ]; then
  state=bad; msg="aim-history.service on VM $VMID: no successful run for $((age / 60)) min"
else
  state=ok; msg="aim-history.service on VM $VMID is OK again"
fi

prev=$(cat "$STATE" 2>/dev/null || echo ok)
echo "aim-history-watch: $state ($msg)"
[ "$state" = "$prev" ] && exit 0
if [ "$state" = bad ]; then
  curl -fsS -m 10 -H "Title: homelab aim history" -H "Priority: high" -H "Tags: rotating_light" \
    -d "$msg" "$TOPIC" >/dev/null || exit 1
else
  curl -fsS -m 10 -H "Title: homelab aim history" -H "Tags: white_check_mark" \
    -d "$msg" "$TOPIC" >/dev/null || exit 1
fi
echo "$state" > "$STATE"
