#!/system/bin/sh
# gpu0805_dual: bind /vendor/lib64 -> self-bootstrapped mirror
MIRROR=/data/adb/gpu805/lib64-mirror
MODDIR=${0%/*}

# 1) first boot: copy pristine /vendor/lib64 as mirror base
if [ ! -f "$MIRROR/.complete" ]; then
  mkdir -p /data/adb/gpu805 2>/dev/null
  rm -rf ${MIRROR}.tmp 2>/dev/null
  cp -a /vendor/lib64 ${MIRROR}.tmp 2>/dev/null || exit 0
  mv ${MIRROR}.tmp "$MIRROR" 2>/dev/null || exit 0
fi

# 2) overlay dual-track files (idempotent)
if [ -d "$MIRROR/egl" ] && [ -d "$MODDIR/files" ]; then
  cp -a $MODDIR/files/. "$MIRROR"/ 2>/dev/null
fi

# 3) labels + bind
chcon u:object_r:vendor_file:s0 "$MIRROR" 2>/dev/null
find "$MIRROR" -type f -exec chcon u:object_r:same_process_hal_file:s0 {} + 2>/dev/null
chcon -R u:object_r:same_process_hal_file:s0 "$MIRROR/egl" "$MIRROR/hw" 2>/dev/null
touch "$MIRROR/.complete" 2>/dev/null

grep -q "lib64-mirror /vendor/lib64 " /proc/mounts 2>/dev/null || mount --bind "$MIRROR" /vendor/lib64 2>/dev/null
exit 0