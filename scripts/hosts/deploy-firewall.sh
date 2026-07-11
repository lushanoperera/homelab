#!/usr/bin/env bash
# Deploy Proxmox host firewall configs to winston or reginald.
#
# Copies hosts/common/cluster.fw + hosts/<host>/firewall/host.fw from the
# repo to the target node's /etc/pve paths, runs pve-firewall compile, and
# reports status. Does NOT flip the enable: flag unless --enable/--disable
# is passed — rollout is manual by design (see hosts/firewall.md).
#
# Usage:
#   scripts/hosts/deploy-firewall.sh <winston|reginald> [flag]
#
#   Flags:
#     (none)     Copy + compile. Do not change enable state.
#     --enable   After copy + compile, flip host.fw enable: 0 → 1.
#     --disable  Flip host.fw enable: 1 → 0 (and pve-firewall stop).
#     --status   Print pve-firewall status + current enable flags. Read-only.
#     --diff     Show diff between repo and remote copies. Read-only.
#
# Requires SSH as root to the target node.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${1:-}"
ACTION="${2:-deploy}"

die() { echo "ERROR: $*" >&2; exit 1; }

case "$HOST" in
  winston)  SSH_TARGET="root@192.168.100.38" ;;
  reginald) SSH_TARGET="root@192.168.100.4"  ;;
  *) die "Usage: $0 <winston|reginald> [--enable|--disable|--status|--diff]" ;;
esac

CLUSTER_FW="$REPO_ROOT/hosts/common/cluster.fw"
HOST_FW="$REPO_ROOT/hosts/$HOST/firewall/host.fw"

[[ -f "$CLUSTER_FW" ]] || die "missing $CLUSTER_FW"
[[ -f "$HOST_FW"    ]] || die "missing $HOST_FW"

status() {
  ssh "$SSH_TARGET" bash -s <<'EOF'
echo "=== pve-firewall status ==="
pve-firewall status
echo
echo "=== cluster.fw enable ==="
grep -E '^enable:' /etc/pve/firewall/cluster.fw || echo "(no enable line)"
echo
echo "=== host.fw enable ==="
grep -E '^enable:' "/etc/pve/nodes/$(hostname)/host.fw" || echo "(no enable line)"
echo
echo "=== deadman armed? ==="
if [[ -f /root/.fw-deadman-armed ]]; then
  ts=$(stat -c %Y /root/.fw-deadman-armed)
  age=$(( $(date +%s) - ts ))
  echo "ARMED ${age}s ago (auto-disable at 600s)"
else
  echo "not armed"
fi
EOF
}

diff_remote() {
  local remote_cluster remote_host
  remote_cluster=$(ssh "$SSH_TARGET" cat /etc/pve/firewall/cluster.fw 2>/dev/null || true)
  remote_host=$(ssh "$SSH_TARGET" "cat /etc/pve/nodes/$HOST/host.fw" 2>/dev/null || true)
  echo "=== cluster.fw (repo vs $HOST) ==="
  diff -u <(cat "$CLUSTER_FW") <(echo "$remote_cluster") || true
  echo
  echo "=== host.fw (repo vs $HOST) ==="
  diff -u <(cat "$HOST_FW") <(echo "$remote_host") || true
}

compile_and_report() {
  echo "=== pve-firewall compile on $HOST ==="
  ssh "$SSH_TARGET" pve-firewall compile
}

safety_check() {
  # Refuse to clobber a live Phase B (policy_in: DROP) with a staged Phase A
  # (policy_in: ACCEPT) unless the operator passes --force.
  local remote_policy repo_policy
  remote_policy=$(ssh "$SSH_TARGET" "grep -E '^policy_in:' /etc/pve/nodes/$HOST/host.fw" 2>/dev/null | awk '{print $2}')
  repo_policy=$(grep -E '^policy_in:' "$HOST_FW" | awk '{print $2}')
  if [[ -n "$remote_policy" && "$remote_policy" == "DROP" && "$repo_policy" != "DROP" ]]; then
    echo "REFUSING: remote host.fw is policy_in: DROP, repo is policy_in: $repo_policy." >&2
    echo "         Deploying would silently revert Phase B back to Phase A." >&2
    echo "         Re-run with --force if this is intentional." >&2
    exit 2
  fi
}

deploy() {
  if [[ "${FORCE:-0}" != 1 ]]; then
    safety_check
  fi
  echo "==> Copying configs to $HOST ($SSH_TARGET)"
  scp "$CLUSTER_FW" "$SSH_TARGET:/etc/pve/firewall/cluster.fw"
  scp "$HOST_FW"    "$SSH_TARGET:/etc/pve/nodes/$HOST/host.fw"
  compile_and_report
  echo
  echo "==> Done. host.fw enable flag NOT changed by default."
  echo "    Flip manually or re-run with --enable after arming the deadman."
  echo
  status
}

flip_enable() {
  local val="$1"
  local remote_path="/etc/pve/nodes/$HOST/host.fw"
  echo "==> Flipping host.fw enable to $val on $HOST"
  ssh "$SSH_TARGET" sed -i "s/^enable:.*/enable: $val/" "$remote_path"
  if [[ "$val" == 0 ]]; then
    ssh "$SSH_TARGET" pve-firewall stop || true
  else
    ssh "$SSH_TARGET" pve-firewall reload
  fi
  status
}

case "$ACTION" in
  deploy)         deploy ;;
  --enable)       deploy; flip_enable 1 ;;
  --disable)      flip_enable 0 ;;
  --status)       status ;;
  --diff)         diff_remote ;;
  --force)        FORCE=1 deploy ;;
  --force-enable) FORCE=1 deploy; flip_enable 1 ;;
  *) die "unknown action: $ACTION" ;;
esac
