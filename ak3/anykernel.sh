### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
### MIX4 ODIN FULL PACK - by ATK12

properties() { '
kernel.string=Mi MIX4 (odin) v50 双档内核 + 144Hz + GPU双档降压 + seccomp真过滤 + Adreno V@0805.0.1 双轨驱动 完整包
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
supported.versions=
supported.patchlevels=
'; }

### AnyKernel install
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
}

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

ui_print " ";
ui_print "***********************************************";
ui_print "  Mi MIX4 (odin) 完整内核包";
ui_print "  内核: v50 均衡/省电双档 (kgsl2023 + 608解锁)";
ui_print "  GPU : 驱动 V@0805.0.1 双轨 + 每档降压两档";
ui_print "  seccomp: 授权App保留真实filter(仅放行reboot)";
ui_print "  144Hz / RF省电 / 档位模块 全集成";
ui_print "  Author: ATK12";
ui_print "***********************************************";
ui_print " ";

. tools/ak3-core.sh;
dump_boot;
write_boot;

## Flash DTBO (current device dtbo)
ui_print " ";
ui_print "Flashing DTBO...";
DTBO_BLOCK=/dev/block/bootdevice/by-name/dtbo;
if [ -b "$DTBO_BLOCK" ]; then
  dd if=$home/dtbo.img of="$DTBO_BLOCK" 2>/dev/null;
  ui_print "DTBO flashed OK.";
else
  ui_print "WARNING: dtbo partition not found, skipping.";
fi

## Flash vendor_boot (GPU per-level -2 undervolt table)
ui_print " ";
ui_print "Flashing vendor_boot (GPU UV -2 levels)...";
VB_BLOCK=/dev/block/bootdevice/by-name/vendor_boot_a;
if [ -b "$VB_BLOCK" ]; then
  dd if=$home/vendor_boot.img of="$VB_BLOCK" 2>/dev/null;
  sync;
  ui_print "vendor_boot flashed OK.";
else
  ui_print "WARNING: vendor_boot_a not found, skipping.";
fi

## Install KSU modules
ui_print " ";
ui_print "Installing KSU modules...";
mount /data >/dev/null 2>&1 || true;
MODROOT=/data/adb/modules;
if [ -d "$MODROOT" ] && [ -w "$MODROOT" ]; then
  # 1) odin_tools
  if [ -d "$home/odin_tools" ]; then
    rm -rf $MODROOT/odin_tools;
    cp -r $home/odin_tools $MODROOT/ 2>/dev/null;
    chmod 755 $MODROOT/odin_tools/bin/* $MODROOT/odin_tools/*.sh 2>/dev/null;
    touch $MODROOT/odin_tools/update 2>/dev/null;
    ui_print "  [1/3] odin_tools (144Hz/触控工具) OK";
  fi
  # 2) sleep_saver_rf
  if [ -d "$home/sleep_saver_rf" ]; then
    rm -rf $MODROOT/sleep_saver_rf;
    cp -r $home/sleep_saver_rf $MODROOT/ 2>/dev/null;
    chmod 755 $MODROOT/sleep_saver_rf/*.sh $MODROOT/sleep_saver_rf/bin/* 2>/dev/null;
    touch $MODROOT/sleep_saver_rf/update 2>/dev/null;
    ui_print "  [2/3] sleep_saver_rf OK";
  fi
  # 4) gpu0805_dual (mirror self-bootstrap on first boot)
  if [ -d "$home/gpu0805_dual" ]; then
    rm -rf $MODROOT/gpu0805_dual;
    cp -r $home/gpu0805_dual $MODROOT/ 2>/dev/null;
    chmod 755 $MODROOT/gpu0805_dual/*.sh 2>/dev/null;
    touch $MODROOT/gpu0805_dual/update 2>/dev/null;
    ui_print "  [3/3] gpu0805_dual OK";
    ui_print "      (首次开机自动构建 lib64 镜像 ~10-30s)";
  fi
  ui_print "Modules installed - reboot to load.";
else
  ui_print "WARNING: /data/adb/modules not writable -";
  ui_print "install modules via KSU Manager instead.";
fi
ui_print " ";
ui_print "All done. Author: ATK12";
ui_print " ";
