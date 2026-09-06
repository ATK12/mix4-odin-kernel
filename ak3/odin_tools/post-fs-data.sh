#!/system/bin/sh
# odin_tools post-fs-data
# 120Hz dfps prop (early)
resetprop -n persist.vendor.dfps.level 120 2>/dev/null
# power mode default (0=balanced 1=eco) - in-kernel odin_mode
DEFAULT_MODE=0
echo $DEFAULT_MODE > /sys/kernel/odin_mode/mode 2>/dev/null
exit 0
