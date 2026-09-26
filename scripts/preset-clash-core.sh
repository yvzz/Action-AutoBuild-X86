#!/bin/bash
# ============================================================
# 下载 OpenClash 运行内核（clash_meta + mihomo）
# 修复原 B 仓库路径错误 + 下载静默失败问题
# ============================================================
set -euo pipefail

OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"
CLASH_KERNEL="${1:-amd64}"

# OpenClash 内核目录（files 目录会被打包进固件）
CORE_DIR="${OPENWRT_PATH}/files/etc/openclash/core"
mkdir -p "$CORE_DIR"

echo "📦 下载 OpenClash 内核 (arch: $CLASH_KERNEL)..."

# 1. Clash Meta 内核
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-${CLASH_KERNEL}.tar.gz"
echo "  ↓ clash_meta from $CLASH_META_URL"
if wget --tries=3 --timeout=60 -qO- "$CLASH_META_URL" | tar xOz > "$CORE_DIR/clash_meta" 2>/dev/null; then
    chmod +x "$CORE_DIR/clash_meta"
    SIZE=$(stat -c%s "$CORE_DIR/clash_meta" 2>/dev/null || stat -f%z "$CORE_DIR/clash_meta" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 100000 ]; then
        echo "  ✅ clash_meta 下载成功 (${SIZE} bytes)"
    else
        echo "  ❌ clash_meta 文件过小，可能下载失败，删除"
        rm -f "$CORE_DIR/clash_meta"
    fi
else
    echo "  ❌ clash_meta 下载失败，跳过"
fi

# 2. Mihomo (Clash.Meta) 内核
MIHOMO_VER="v1.19.0"
MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VER}/mihomo-linux-${CLASH_KERNEL}-${MIHOMO_VER}.gz"
echo "  ↓ mihomo from $MIHOMO_URL"
if wget --tries=3 --timeout=60 -qO /tmp/mihomo.gz "$MIHOMO_URL" 2>/dev/null; then
    if gunzip -c /tmp/mihomo.gz > "$CORE_DIR/mihomo" 2>/dev/null; then
        chmod +x "$CORE_DIR/mihomo"
        SIZE=$(stat -c%s "$CORE_DIR/mihomo" 2>/dev/null || stat -f%z "$CORE_DIR/mihomo" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 100000 ]; then
            echo "  ✅ mihomo 下载成功 (${SIZE} bytes)"
        else
            echo "  ❌ mihomo 文件过小，删除"
            rm -f "$CORE_DIR/mihomo"
        fi
    else
        echo "  ❌ mihomo 解压失败，跳过"
    fi
else
    echo "  ❌ mihomo 下载失败，跳过"
fi
rm -f /tmp/mihomo.gz

# 3. GeoIP 数据库
echo "  ↓ GeoIP/GeoSite 数据库..."
wget --tries=3 --timeout=30 -qO "$OPENWRT_PATH/files/etc/openclash/Country.mmdb" \
    "https://raw.githubusercontent.com/alecthw/mmdb_china_ip_list/release/lite/Country.mmdb" 2>/dev/null && \
    echo "  ✅ Country.mmdb" || echo "  ⚠️ Country.mmdb 下载失败"

wget --tries=3 --timeout=30 -qO "$OPENWRT_PATH/files/etc/openclash/GeoIP.dat" \
    "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat" 2>/dev/null && \
    echo "  ✅ GeoIP.dat" || echo "  ⚠️ GeoIP.dat 下载失败"

wget --tries=3 --timeout=30 -qO "$OPENWRT_PATH/files/etc/openclash/GeoSite.dat" \
    "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat" 2>/dev/null && \
    echo "  ✅ GeoSite.dat" || echo "  ⚠️ GeoSite.dat 下载失败"

echo "📦 OpenClash 内核下载步骤完成"