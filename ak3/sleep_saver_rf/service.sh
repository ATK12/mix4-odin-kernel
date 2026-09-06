#!/system/bin/sh
# sleep-saver service: late_start, 开机自启守护
MODDIR=/data/adb/modules/sleep_saver_rf
LOG=$MODDIR/.saver.log

# wait for boot completed
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
    sleep 2
    i=$((i+1))
done
sleep 15

# 拷贝守护到可执行位置并启动
cp $MODDIR/bin/sleep_saver.sh /data/local/tmp/sleep_saver.sh 2>/dev/null
chmod 755 /data/local/tmp/sleep_saver.sh
# setsid 独立会话 + 全部 stdout/stderr 指向 /dev/null (binder SELinux 经验)
setsid sh /data/local/tmp/sleep_saver.sh > /dev/null 2>&1 < /dev/null &
echo "[$(date +%H:%M:%S)] sleep-saver started" >> $LOG
exit 0
