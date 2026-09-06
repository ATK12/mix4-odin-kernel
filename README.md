# MIX4 (odin) 定制内核 — 构建工作流

Mi MIX4 (SM8350 / MIUI 12.5.2.0 / 5.4.86-qgki / kgsl2023) 定制内核源码与自动化编译流水线。

## 仓库内容

| 路径 | 说明 |
|---|---|
| odin_patch/ | 内核改动层(覆盖式补丁,带 [odin] 标注):双档电源 / 608 解锁 / seccomp 真过滤 / 自检节点 |
| config/ | 最终内核配置 v50susfs_prod.cfg |
| local/builder_odin.sh | 构建脚本(本地或云端通用) |
| tools/pack_boot.py | boot.img 打包(新 Image + 原厂 ramdisk) |
| .github/workflows/build.yml | GitHub Actions 云端编译 |

## 资源(Release v50-full-ATK12)

- `odin-base-src.tar.zst` — 完整可编译源树快照(含 KernelSU;197MB)
- `cur_boot.img` — 原厂 boot(ramdisk 基座,打包用)
- `odin-v50-full-ATK12.zip` — 成品刷机包(含 dtbo/vendor_boot/模块)

## 用法

### 云端(GitHub Actions)

1. Actions 页 → "MIX4 odin kernel build" → Run workflow
2. 编译约 20~40 分钟(首次;后续有 ccache 缓存更快)
3. 产物 Image / boot.img 在本次运行的 Artifacts 里下载

### 本地(Linux/WSL)

```bash
# 方式一:用本地已有源树(如 WSL 构建树)
bash local/builder_odin.sh --tree /path/to/kernel/source --jobs 16

# 方式二:下载源包从零构建
bash local/builder_odin.sh --fetch-pack https://github.com/ATK12/mix4-odin-kernel/releases/download/v50-full-ATK12/odin-base-src.tar.zst --jobs 16

# 产物: out-artifacts/Image
# 打包 boot.img:
python3 tools/pack_boot.py out-artifacts/Image cur_boot.img out-artifacts/boot.img
```

### 更新源包(内核源树有重大更新后)

```bash
tar --exclude=./out --exclude=./KernelSU.orig-* -I "zstd -T0 -19" -cf odin-base-src.tar.zst -C <源树> .
# 然后替换 Release v50-full-ATK12 里的同名 asset(先删旧再传新)
```

## Fork 提示

- fork 后把 .github/workflows/build.yml 顶部 env 的 REPO 改成自己的仓库
- 资源 asset 若用自己仓库的 Release,同步替换 BASE_TAG

Author: ATK12