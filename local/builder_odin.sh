#!/bin/bash
# =====================================================================
# MIX4 (odin) kernel builder - local / GitHub Actions shared
# Usage:
#   bash local/builder_odin.sh --tree <kernel-src-dir>
#   bash local/builder_odin.sh --fetch-pack <src-pack-url> [--clang-pack <clang-url>]
#   optional: --clang <dir> --ccache <dir> --jobs N --out <dir>
# Output: <out>/Image
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
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

# ---- source tree ----
if [ -n "$FETCH_PACK" ]; then
  echo ">>> fetch src pack: $FETCH_PACK"
  mkdir -p "$WORK"
  curl -L --retry 3 -o "$WORK/src.tar.zst" "$FETCH_PACK"
  echo ">>> unpack src ..."
  mkdir -p "$WORK/src"
  tar -I zstd -xf "$WORK/src.tar.zst" -C "$WORK/src"
  TREE="$WORK/src"
elif [ -n "$TREE" ]; then
  [ -d "$TREE/kernel" ] || { echo "error: $TREE has no kernel/"; exit 1; }
else
  echo "error: need --tree or --fetch-pack"; exit 1
fi
echo ">>> tree: $TREE"

# ---- toolchain ----
if [ -z "$CLANG_DIR" ]; then
  CLANG_DIR="$WORK/clang1102"
  if [ ! -x "$CLANG_DIR/bin/clang" ]; then
    if [ -z "$CLANG_PACK" ]; then
      echo "error: no clang found; pass --clang <dir> or --clang-pack <url>"
      exit 1
    fi
    echo ">>> fetch clang pack: $CLANG_PACK"
    mkdir -p "$WORK"
    curl -L --retry 3 -o "$WORK/clang.tar.zst" "$CLANG_PACK"
    tar -I zstd -xf "$WORK/clang.tar.zst" -C "$WORK"
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

# ---- apply odin overlay (idempotent) ----
echo ">>> apply odin_patch ..."
cp -a "$PATCH_DIR/." "$TREE/"
grep -q "\[odin" "$TREE/kernel/seccomp.c" || { echo "error: odin_patch verify failed"; exit 1; }

# ---- config + build ----
echo ">>> config ..."
mkdir -p "$TREE/out"
cp "$CFG" "$TREE/out/.config"
cd "$TREE"
MAKEFLAGS="ARCH=arm64 O=out LLVM=1 CC=clang HOSTCC=gcc CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"
echo ">>> olddefconfig ..."
make $MAKEFLAGS olddefconfig < /dev/null
echo ">>> build Image (jobs=$JOBS) ..."
make $MAKEFLAGS -j"$JOBS" Image

# ---- output ----
mkdir -p "$OUT_DIR"
cp -v "$TREE/out/arch/arm64/boot/Image" "$OUT_DIR/Image"
echo "=========================================="
echo "done: $OUT_DIR/Image"
sha256sum "$OUT_DIR/Image"
echo "=========================================="
