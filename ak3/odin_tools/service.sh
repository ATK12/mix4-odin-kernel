#!/system/bin/sh
# MIX4 120Hz default: late_start service (v7.2)
# - Enforce 120Hz after boot completed
# - Daemon (bin/daemon.sh) setsid 独立会话启动
# - v7.2 关键修复: 所有 settings/cmd binder 调用的 stdout 必须指向 /dev/null,
#   否则 cmd 在 system_server 内执行时会向继承的 fd(=模块日志文件)追加输出,
#   SELinux 拒绝 (system_server 不能写 adb_data_file) 导致 Failed transaction

MODDIR=/data/adb/modules/odin_tools
FLAG=$MODDIR/.user_set
LOG=$MODDIR/.fps144.log

# wait for boot
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
    sleep 2
    i=$((i+1))
done
sleep 10

# Initial apply 120Hz (module default) - binder 命令 stdout 全部 >/dev/null
settings put secure miui_refresh_rate 120 >/dev/null 2>&1
settings put system min_refresh_rate 120 >/dev/null 2>&1
settings put system user_refresh_rate 120 >/dev/null 2>&1
settings put system peak_refresh_rate 120 >/dev/null 2>&1
resetprop -n persist.vendor.dfps.level 120 2>/dev/null
rm -f "$FLAG" 2>/dev/null
echo "$(date '+%m-%d %H:%M:%S') boot: set 120Hz OK" >> "$LOG" 2>/dev/null

# ---- v3: tombstone (cached_apps_freezer) ----
device_config put activity_manager_native_boot cached_apps_freezer enabled >/dev/null 2>&1

# ---- v3: memory sysctl ----
echo 100 > /proc/sys/vm/swappiness 2>/dev/null
echo 150 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null

# ---- v4/v7: disable low-usage apps + zram compress (setsid bg, stdio=/dev/null) ----
setsid sh "$MODDIR/bin/optimize.sh" all < /dev/null > /dev/null 2>&1 &
echo "$(date '+%m-%d %H:%M:%S') optimize: started (setsid bg)" >> "$LOG" 2>/dev/null

# ---- v7.1/7.2: anti-fallback daemon (setsid, stdio=/dev/null) ----
setsid sh "$MODDIR/bin/daemon.sh" < /dev/null > /dev/null 2>&1 &
echo "$(date '+%m-%d %H:%M:%S') daemon: started (setsid)" >> "$LOG" 2>/dev/null

exit 0