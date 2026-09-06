#!/system/bin/sh
# odin power modes: 0=balanced(default) 1=eco
MODE="${1:-0}"
S=/sys

[ -w $S/kernel/odin_mode/mode ] || { echo "odin_mode not available"; exit 1; }

# 1) release stale thermal caps (always allowed)
for f in $S/class/thermal/cooling_device*/type; do
  t=$(cat "$f" 2>/dev/null)
  case "$t" in
    thermal-cpufreq-*|thermal-devfreq-*|cpu-isolate*)
      echo 0 > "${f%/type}/cur_state" 2>/dev/null ;;
  esac
done

# 2) kernel mode (thermal policy + caps applied in-kernel)
echo "$MODE" > $S/kernel/odin_mode/mode 2>/dev/null

case "$MODE" in
  1)
    # ECO handled by kernel tunables; explicit caps for safety:
    echo 1800000 > $S/devices/system/cpu/cpufreq/policy7/scaling_max_freq 2>/dev/null
    echo 1600000 > $S/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2>/dev/null
    echo 1200000 > $S/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null
    echo 540000000 > $S/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
    ;;
  0)
    for p in 0 4 7; do
      max=$(cat $S/devices/system/cpu/cpufreq/policy$p/cpuinfo_max_freq 2>/dev/null)
      [ -n "$max" ] && echo "$max" > $S/devices/system/cpu/cpufreq/policy$p/scaling_max_freq 2>/dev/null
    done
    echo 840000000 > $S/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
    ;;
esac
echo "odin_mode: $MODE"