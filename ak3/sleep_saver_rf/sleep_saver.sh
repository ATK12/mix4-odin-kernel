#!/system/bin/sh
# sleep-saver v1.3: 深睡射频省电守护 (root) - 恢复用户实际状态, 不强制开启
# ACTIVE(亮屏) --灭屏60s--> SAVING --来电--> CALL --挂断--> SAVING --亮屏--> ACTIVE
# v1.3: 进入省电前保存 data/bt/gps 实际状态, 恢复时还原(用户手动关闭不会被强制打开)

LOG=/data/local/tmp/sleep_saver.log
STATE_FILE=/data/local/tmp/sleep_saver.state
PREF_NET_ACTIVE="32,33"
PREF_NET_SAVE="11"
state=ACTIVE
screen_off_since=0
SAVE_DATA=1
SAVE_BT=1
SAVE_LOC=3

log() { echo "[$(date +%H:%M:%S)] $1" >> $LOG; }

get_screen() {
  dumpsys power 2>/dev/null | grep -oE "mWakefulness=[A-Za-z]+" | head -1 | cut -d= -f2
}

get_call() {
  dumpsys telephony.registry 2>/dev/null | grep -oE "mCallState=[0-9]+" | head -1 | cut -d= -f2
}

apply_radio() { settings put global preferred_network_mode $1; }

get_data() { settings get global mobile_data 2>/dev/null; }
get_bt() { settings get global bluetooth_on 2>/dev/null; }
get_loc() { settings get secure location_mode 2>/dev/null; }

set_data() {
  if [ "$1" = "0" ]; then
    svc data disable 2>/dev/null; settings put global mobile_data 0
  else
    settings put global mobile_data 1; svc data enable 2>/dev/null
  fi
}
set_bt() { settings put global bluetooth_on $1; }
set_loc() { settings put secure location_mode $1; }

# 保存用户当前实际状态
remember_state() {
  SAVE_DATA=$(get_data)
  SAVE_BT=$(get_bt)
  SAVE_LOC=$(get_loc)
  [ -z "$SAVE_DATA" ] && SAVE_DATA=1
  [ -z "$SAVE_BT" ] && SAVE_BT=1
  [ -z "$SAVE_LOC" ] && SAVE_LOC=3
  log "  remember user state: data=$SAVE_DATA bt=$SAVE_BT loc=$SAVE_LOC"
}

enter_saving() {
  log "ENTER SAVING"
  remember_state
  apply_radio $PREF_NET_SAVE
  set_data 0
  set_loc 0
  set_bt 0
  log "  [SAVE] radio=LTE-only data=off gps=off bt=off"
}

exit_saving() {
  log "EXIT SAVING"
  apply_radio $PREF_NET_ACTIVE
  set_data "$SAVE_DATA"
  set_loc "$SAVE_LOC"
  set_bt "$SAVE_BT"
  log "  [RESTORE] radio=$PREF_NET_ACTIVE data=$SAVE_DATA gps=$SAVE_LOC bt=$SAVE_BT"
}

log "=== sleep-saver v1.3 started (ACTIVE, no forced enables) ==="

while true; do
  scr=$(get_screen)
  call=$(get_call)
  case $state in
    ACTIVE)
      if [ "$scr" = "Dozing" ] || [ "$scr" = "Asleep" ]; then
        if [ $screen_off_since -eq 0 ]; then screen_off_since=$(date +%s); fi
        now=$(date +%s)
        if [ $((now - screen_off_since)) -ge 60 ]; then
          enter_saving; state=SAVING; screen_off_since=0
        fi
      else
        screen_off_since=0
      fi
      ;;
    SAVING)
      if [ "$call" = "1" ] || [ "$call" = "2" ]; then
        log "CALL DETECTED"; exit_saving; state=CALL
      elif [ "$scr" = "Awake" ]; then
        log "SCREEN ON -> ACTIVE"; exit_saving; state=ACTIVE
      fi
      ;;
    CALL)
      if [ "$call" = "0" ] && [ "$scr" != "Awake" ]; then
        log "CALL END -> SAVING"; enter_saving; state=SAVING
      elif [ "$scr" = "Awake" ]; then
        state=ACTIVE
      fi
      ;;
  esac
  echo $state > $STATE_FILE
  sleep 2
done
