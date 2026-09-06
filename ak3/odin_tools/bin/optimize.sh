#!/system/bin/sh
# optimize.sh - 内存优化 v2: 禁用低利用率系统应用 + zram 压缩保留应用
# 用法: sh optimize.sh <disable|compress|all>
# 兼容 toybox ash

LOG=/data/adb/modules/odin_tools/.optimize.log
mkdir -p "$(dirname "$LOG")" 2>/dev/null

# 按包名匹配取 pid 列表 (grep 精确匹配进程名, 避免误伤)
pids_of() {
    ps -A -o PID,NAME 2>/dev/null | grep " $1" | awk '{print $1}'
}

# zram 压缩: 把匿名页换出到 zram, 立即释放内存, 进程保留可用
compress_pkg() {
    for pid in $(pids_of "$1"); do
        [ -z "$pid" ] && continue
        echo 1000 > /proc/$pid/reclaim 2>/dev/null
        echo "$(date '+%m-%d %H:%M:%S') compress: $1 pid=$pid" >> "$LOG" 2>/dev/null
    done
}

# 禁用系统应用: 永久阻止启动 (GMS/广告等低利用率)
DISABLE_LIST="com.google.android.gms com.google.android.gsf com.google.android.syncadapters.contacts com.google.android.ext.services com.google.android.onetimeinitializer com.miui.systemAdSolution com.miui.analytics"

# 禁用单个包: 内置重试 (开机时 PackageManager 未就绪会报 "Failed transaction",
# v7: 失败后每 6s 重试, 最多 5 次, 成功/失败都记入日志)
disable_one() {
    p="$1"
    tries=0
    while [ $tries -lt 5 ]; do
        out=$(pm disable-user --user 0 "$p" 2>&1)
        rc=$?
        case "$out" in
            *"Failed transaction"*) rc=1 ;;
        esac
        if [ "$rc" -eq 0 ]; then
            echo "$(date '+%m-%d %H:%M:%S') disable OK: $p (try $((tries+1)))" >> "$LOG" 2>/dev/null
            return 0
        fi
        tries=$((tries+1))
        [ $tries -lt 5 ] && sleep 6
    done
    echo "$(date '+%m-%d %H:%M:%S') disable FAILED: $p after 5 tries: $out" >> "$LOG" 2>/dev/null
    return 1
}

disable_all() {
    for p in $DISABLE_LIST; do
        disable_one "$p"
    done
}

# 压缩名单: 保留可用, 只省内存
CONNECT="com.miui.mishare.connectivity com.xiaomi.mi_connect_service"
VOICE="com.miui.voiceassist"

case "$1" in
    disable)
        disable_all
        echo "disable done"
        ;;
    compress)
        for p in $CONNECT $VOICE; do compress_pkg "$p"; done
        echo "compress done"
        ;;
    all)
        disable_all
        for p in $CONNECT $VOICE; do compress_pkg "$p"; done
        echo "all done"
        ;;
    *)
        echo "usage: optimize.sh <disable|compress|all>"
        ;;
esac
