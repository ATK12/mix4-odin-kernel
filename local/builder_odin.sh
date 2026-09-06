#!/bin/bash
# =====================================================================
# MIX4 (odin) 内核构建脚本 — 本地 / GitHub Actions 通用
# 用法:
#   bash local/builder_odin.sh --tree <源树路径>            # 用本地已有源树
#   bash local/builder_odin.sh --fetch-pack <URL>           # 下载基线源包后构建
#   可选: --clang <dir> --ccache <dir> --jobs N --out <dir>
# 产物: <out>/Image  (boot 内核镜像)
# =====================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

TREE=""
FETCH_PACK=""
CLANG_DIR=""
CLANG_PACK=""
CCACHE_DIR=""
JOBS="$(nproc 2>/dev/null || echo 4)"
OUT_DIR="$PWD/out-artifacts"
CFG="$SCRIPT_DIR/config/v50susfs_prod.cfg"
PATCH_DIR="$SCRIPT_DIR/odin_patch"
WORK="$PWD/work"

while [ $# -gt 0 ]; do
  case "$1" in
    --tree) TREE="$2"; shift 2;;
    --fetch-pack) FETCH_PACK="$2"; shift 2;;
    --clang) CLANG_DIR="$2"; shift 2;;
    --clang-pack) CLANG_PACK="$2"; shift 2;;
    --ccache) CCACHE_DIR="$2"; shift 2;;
    --jobs) JOBS="$2"; shift 2;;
    --out) OUT_DIR="$2"; shift 2;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

# ---- 获取/校验源树 ----
if [ -n "$FETCH_PACK" ]; then
  echo ">>> 下载基线源包: $FETCH_PACK"
  mkdir -p "$WORK"
  curl -L --retry 3 -o "$WORK/src.tar.zst" "$FETCH_PACK"
  echo ">>> 解压源包(约1-2分钟)..."
  mkdir -p "$WORK/src"
  tar -I zstd -xf "$WORK/src.tar.zst" -C "$WORK/src"
  TREE="$WORK/src"
elif [ -n "$TREE" ]; then
  [ -d "$TREE/kernel" ] || { echo "错误: $TREE 不是内核树(缺少 kernel/)"; exit 1; }
else
  echo "错误: 需要 --tree <path> 或 --fetch-pack <url>"; exit 1
fi
echo ">>> 源树: $TREE"

# ---- 工具链 ----
if [ -z "$CLANG_DIR" ]; then
  CLANG_DIR="$WORK/clang-r416183b"
  if [ ! -x "$CLANG_DIR/bin/clang" ]; then
    echo ">>> 下载 clang-r416183b (Android prebuilt clang 11)..."
    mkdir -p "$WORK"
    curl -L --retry 3 -o "$WORK/clang.tar.gz"       "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r416183b.tar.gz"
    mkdir -p "$CLANG_DIR"
    tar -xzf "$WORK/clang.tar.gz" -C "$CLANG_DIR"
  fi
fi
export PATH="$CLANG_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$CLANG_DIR/lib:$CLANG_DIR/lib64:$LD_LIBRARY_PATH"

# ---- ccache ----
if [ -n "$CCACHE_DIR" ]; then
  export CCACHE_DIR="$CCACHE_DIR"
  export CCACHE_COMPRESS=1
  mkdir -p "$CCACHE_DIR"
  echo ">>> ccache: $CCACHE_DIR"
fi

# ---- 应用 odin 补丁层(覆盖式,幂等) ----
echo ">>> 应用 odin_patch ..."
cp -a "$PATCH_DIR/." "$TREE/"
grep -q '\[odin' "$TREE/kernel/seccomp.c" || { echo "错误: odin_patch 应用校验失败"; exit 1; }

# ---- 配置与编译 ----
echo ">>> 生成配置 ..."
mkdir -p "$TREE/out"
cp "$CFG" "$TREE/out/.config"
cd "$TREE"
MAKEFLAGS="ARCH=arm64 O=out LLVM=1 CC=clang HOSTCC=gcc CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"
echo ">>> olddefconfig ..."
make $MAKEFLAGS olddefconfig < /dev/null
echo ">>> 编译 Image (jobs=$JOBS) ..."
make $MAKEFLAGS -j"$JOBS" Image

# ---- 产物 ----
mkdir -p "$OUT_DIR"
cp -v "$TREE/out/arch/arm64/boot/Image" "$OUT_DIR/Image"
echo "=========================================="
echo "构建完成: $OUT_DIR/Image"
sha256sum "$OUT_DIR/Image"
echo "=========================================="
