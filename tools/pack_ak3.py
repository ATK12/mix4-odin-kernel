#!/usr/bin/env python3
# pack_ak3.py - assemble the full AK3 flashable zip
# usage: pack_ak3.py <Image> <dtbo> <vendor_boot> <gpu0805_files_dir_or_None> <staging_ak3_dir> <out.zip>
import sys, os, zipfile

img_p, dtbo_p, vb_p, gpu_files, ak3_dir, out_p = sys.argv[1:7]
if os.path.exists(out_p):
    os.remove(out_p)

zf = zipfile.ZipFile(out_p, "w", zipfile.ZIP_DEFLATED, compresslevel=6)

def add(p, arc=None):
    if arc is None:
        arc = os.path.relpath(p, os.path.dirname(p))
    zf.write(p, arc)

# 1) 骨架(anykernel.sh/META-INF/tools/模块脚本)
for root, dirs, files in os.walk(ak3_dir):
    for f in files:
        p = os.path.join(root, f)
        zf.write(p, os.path.relpath(p, ak3_dir))
# 2) 内核与静态镜像
add(img_p, "Image")
add(dtbo_p, "dtbo.img")
add(vb_p, "vendor_boot.img")
# 3) GPU 驱动库 -> gpu0805_dual/files/
if gpu_files != "none" and os.path.isdir(gpu_files):
    for root, dirs, files in os.walk(gpu_files):
        for f in files:
            p = os.path.join(root, f)
            zf.write(p, os.path.join("gpu0805_dual", "files", os.path.relpath(p, gpu_files)))
zf.close()
print("ak3 zip done:", os.path.getsize(out_p))
