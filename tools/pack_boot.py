#!/usr/bin/env python3
# pack_boot.py - 把新 Image 打进 base boot 镜像(保留 ramdisk 与 header)
# 用法: python3 pack_boot.py <Image> <base_boot.img> <out.img>
import struct, sys, hashlib

img_path, base_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(base_path, "rb").read()
img = open(img_path, "rb").read()
hsz = struct.unpack("<I", data[0x14:0x18])[0]
ksz = struct.unpack("<I", data[8:12])[0]
rsz = struct.unpack("<I", data[12:16])[0]
assert data[:8] == b"ANDROID!", "not a boot image"
r_start = ((4096 + ksz + 4095) // 4096) * 4096
ramdisk = data[r_start:r_start + rsz]

def a4096(x):
    return ((x + 4095) // 4096) * 4096

h = bytearray(data[:hsz])
struct.pack_into("<I", h, 8, len(img))
struct.pack_into("<I", h, 12, len(ramdisk))
out = bytes(h) + bytes(4096 - len(h)) + img + bytes(a4096(4096 + len(img)) - (4096 + len(img))) + ramdisk
# 补齐到 base 原始分区大小(从文件总长推断,若 base 是分区镜像)
if len(out) < len(data):
    out = out + bytes(len(data) - len(out))
open(out_path, "wb").write(out)
print("written:", out_path, len(out))
print("img sha256:", hashlib.sha256(img).hexdigest())
