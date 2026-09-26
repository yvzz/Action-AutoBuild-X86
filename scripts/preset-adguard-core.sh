#!/bin/bash
# ============================================================
# 下载 AdGuardHome 核心
# 修复原 B 仓库路径错误 + 下载失败检测
# ============================================================
set -euo pipefail

OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"
CLASH_KERNEL="${1:-amd64}"

# 映射架构名
case "$CLASH_KERNEL" in
    amd64) ARCH="x86_64" ;;
    arm64) ARCH="arm64" ;;
    arm)   ARCH="armv7" ;;
    *)     ARCH="$CLASH_KERNEL" ;;
esac

AGH_DIR="${OPENWRT_PATH}/files/usr/bin/AdGuardHome"
mkdir -p "$AGH_DIR"

AGH_VER="v0.107.52"
AGH_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_VER}/AdGuardHome_linux_${ARCH}.tar.gz"

echo "📦 下载 AdGuardHome 核心 (arch: $ARCH)..."
echo "  ↓ $AGH_URL"

if wget --tries=3 --timeout=60 -qO /tmp/agh.tar.gz "$AGH_URL" 2>/dev/null; then
    if tar xzf /tmp/agh.tar.gz -C /tmp AdGuardHome/AdGuardHome --strip-components=1 2>/dev/null; then
        mv /tmp/AdGuardHome "$AGH_DIR/AdGuardHome"
        chmod +x "$AGH_DIR/AdGuardHome"
        SIZE=$(stat -c%s "$AGH_DIR/AdGuardHome" 2>/dev/null || stat -f%z "$AGH_DIR/AdGuardHome" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 1000000 ]; then
            echo "  ✅ AdGuardHome 下载成功 (${SIZE} bytes)"
        else
            echo "  ❌ AdGuardHome 文件过小，删除"
            rm -f "$AGH_DIR/AdGuardHome"
        fi
    else
        echo "  ❌ AdGuardHome 解压失败"
    fi
else
    echo "  ⚠️ AdGuardHome 下载失败，跳过（固件运行时会自查下载）"
fi
rm -f /tmp/agh.tar.gz /tmp/AdGuardHome

echo "📦 AdGuardHome 核心下载步骤完成"