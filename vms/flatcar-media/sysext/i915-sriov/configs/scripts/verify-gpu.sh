#!/usr/bin/env bash
# verify-gpu.sh — GPU verification for i915-sriov sysext on Flatcar VM 100
# Runs on the VM. Exit 0 if all critical checks pass, exit 1 if any fail.
set -uo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"  # "ok" or "fail"
  if [ "$result" = "ok" ]; then
    printf "  [PASS] %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  [FAIL] %s\n" "$desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== GPU Verification (i915-sriov sysext) ==="
echo ""

# 1. PCI VGA device exists
if lspci 2>/dev/null | grep -qi vga; then
  check "PCI VGA device visible" "ok"
else
  check "PCI VGA device visible" "fail"
fi

# 2. /dev/dri directory exists
if [ -d /dev/dri ]; then
  check "/dev/dri directory exists" "ok"
else
  check "/dev/dri directory exists" "fail"
fi

# 3. At least one renderD* device exists
RENDER_DEV=$(ls /dev/dri/renderD* 2>/dev/null | head -1)
if [ -n "$RENDER_DEV" ]; then
  check "renderD device exists ($RENDER_DEV)" "ok"
else
  check "renderD device exists" "fail"
fi

# 4. renderD device has correct permissions (660, group render)
if [ -n "$RENDER_DEV" ]; then
  PERMS=$(stat -c %a "$RENDER_DEV" 2>/dev/null)
  GROUP=$(stat -c %G "$RENDER_DEV" 2>/dev/null)
  if [ "$PERMS" = "660" ] && [ "$GROUP" = "render" ]; then
    check "renderD permissions (660, group=render)" "ok"
  else
    check "renderD permissions (660, group=render) — got ${PERMS:-?} group=${GROUP:-?}" "fail"
  fi
else
  check "renderD permissions (660, group=render) — no renderD device" "fail"
fi

# 5. card* device exists
if ls /dev/dri/card* >/dev/null 2>&1; then
  check "card device exists" "ok"
else
  check "card device exists" "fail"
fi

# 6. i915 module is loaded
if [ -d /sys/module/i915 ]; then
  check "i915 module loaded" "ok"
else
  check "i915 module loaded" "fail"
fi

# 7. Running module is the SR-IOV patched version (not stock).
# modinfo -F filename reads the stale index on Flatcar (read-only /lib/modules),
# so check the running module's version via /sys or dmesg instead.
MODULE_VER=$(cat /sys/module/i915/version 2>/dev/null || dmesg | grep -oP 'i915-sriov-dkms' | head -1)
if echo "$MODULE_VER" | grep -qi "sriov"; then
  check "i915 is SR-IOV patched version ($MODULE_VER)" "ok"
else
  check "i915 is SR-IOV patched version — got ${MODULE_VER:-unknown}" "fail"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

exit $((FAIL > 0 ? 1 : 0))
