#!/system/bin/sh
# daemon.sh - 120Hz 防回落守护 (由 service.sh 以 setsid 独立会话启动,
# v7.2: setsid 脱离 ksud + binder 命令 stdout 指向 /dev/null (防 system_server fd 污染)
MODDIR=/data/adb/modules/odin_tools
FLAG=$MODDIR/.user_set
LOG=$MODDIR/.fps144.log
while true; do
    sleep 15

    # User manually set? Keep that value (system perf may overwrite refresh settings -> flicker)
    if [ -f "$FLAG" ]; then
        US="$(cat "$FLAG" 2>/dev/null)"
        case "$US" in ''|*[!0-9]*) US=120 ;; esac
        CUR="$(settings get system peak_refresh_rate 2>/dev/null)"
        CUR_PROP="$(getprop persist.vendor.dfps.level)"
        if [ "$CUR" != "$US" ] || [ "$CUR_PROP" != "$US" ]; then
            settings put secure miui_refresh_rate "$US" >/dev/null 2>&1
            settings put system min_refresh_rate "$US" >/dev/null 2>&1
            settings put system user_refresh_rate "$US" >/dev/null 2>&1
            settings put system peak_refresh_rate "$US" >/dev/null 2>&1
            resetprop -n persist.vendor.dfps.level "$US" 2>/dev/null
            echo "$(date '+%m-%d %H:%M:%S') keep: us=$US peak=$CUR dfps=$CUR_PROP -> $US" >> "$LOG" 2>/dev/null
        fi
        continue
    fi

    # Power-saver on? Allow 60Hz.
    LP="$(settings get global low_power 2>/dev/null)"
    if [ "$LP" = "1" ]; then
        continue
    fi

    # Check current peak_refresh_rate
    CUR="$(settings get system peak_refresh_rate 2>/dev/null)"
    CUR_PROP="$(getprop persist.vendor.dfps.level)"

    NEED_FIX=0
    case "$CUR" in
        60|90|144) NEED_FIX=1 ;;
    esac
    case "$CUR_PROP" in
        60|90|144) NEED_FIX=1 ;;
    esac

    if [ "$NEED_FIX" = "1" ]; then
        # v7: 全键同步
        settings put secure miui_refresh_rate 120 >/dev/null 2>&1
        settings put system min_refresh_rate 120 >/dev/null 2>&1
        settings put system user_refresh_rate 120 >/dev/null 2>&1
        settings put system peak_refresh_rate 120 >/dev/null 2>&1
        resetprop -n persist.vendor.dfps.level 120 2>/dev/null
        echo "$(date '+%m-%d %H:%M:%S') restore: was peak=$CUR dfps=$CUR_PROP miui=$(settings get secure miui_refresh_rate) -> 120 (4keys+prop)" >> "$LOG" 2>/dev/null
    fi
done