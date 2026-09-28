#!/bin/bash
# ============================================================
# ImmortalWrt DIY 脚本 — 融合 A 仓库工程化 + B 仓库透明性
# 支持 openwrt-24.10 和 master 两个分支
# ============================================================
set -eo pipefail

# 克隆失败不中断编译（关键包除外）
CLONE_FATAL=false
clone_fail() { CLONE_FATAL=true; }

# ------------------------------------------------------------
# 工具函数：git clone 辅助（吸收自 A 仓库，简化版）
# ------------------------------------------------------------

# 克隆整个仓库到 package/
# 用法: git_clone <url> [target_dir]
#       git_clone -b <branch> <url> [target_dir]
git_clone() {
    local branch="" target_dir
    if [[ "$1" == "-b" ]]; then
        branch="-b $2 --single-branch"
        shift 2
    fi
    local repo_url="$1"; shift
    target_dir="${1:-${repo_url##*/}}"
    git clone -q $branch --depth=1 "$repo_url" "package/$target_dir" 2>/dev/null || {
        echo "  ⚠️  跳过: $repo_url (分支不存在或网络错误)"
        rm -rf "package/$target_dir" 2>/dev/null
        return 0
    }
    rm -rf "package/$target_dir/{.git*,README*.md,LICENSE}"
    echo "  ✅ 添加: $target_dir"
}

# 稀疏克隆指定目录到 package/
git_sparse_clone() {
    local branch="$1" repourl="$2"; shift 2
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" /tmp/sparse-clone
    cd /tmp/sparse-clone && git sparse-checkout set "$@"
    mv -f "$@" "$GITHUB_WORKSPACE/openwrt/package/"
    cd "$GITHUB_WORKSPACE/openwrt" && rm -rf /tmp/sparse-clone
    echo "  ✅ 稀疏克隆: $@"
}

# 克隆仓库中所有子目录到 package/
git_clone_all() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"; shift
    else
        branch="-b $1 --single-branch"; repo_url="$2"; shift 2
    fi
    git clone -q $branch --depth=1 "$repo_url" "$temp_dir" 2>/dev/null || {
        echo "  ⚠️  跳过: $repo_url (分支不存在或网络错误)"
        rm -rf "$temp_dir"; return 0
    }
    for d in "$temp_dir"/*/; do
        [ -d "$d" ] && cp -rf "$d" package/
    done
    rm -rf "$temp_dir"
    echo "  ✅ 全量克隆: $repo_url"
}

# ------------------------------------------------------------
# 1. 修改默认 IP
# ------------------------------------------------------------
sed -i 's/192.168.1.1/10.0.0.252/g' package/base-files/files/bin/config_generate

# ------------------------------------------------------------
# 2. TTYD 免登录
# ------------------------------------------------------------
TTYD_CONFIG="feeds/packages/utils/ttyd/files/ttyd.config"
if [ -f "$TTYD_CONFIG" ]; then
    sed -i 's|/bin/login|/bin/login -f root|g' "$TTYD_CONFIG"
fi

# ------------------------------------------------------------
# 3. 设置 root 密码为 password
# ------------------------------------------------------------
sed -i 's/root:::0:99999:7:::/root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' package/base-files/files/etc/shadow

# ------------------------------------------------------------
# 4. 添加第三方插件
# ------------------------------------------------------------
echo "📦 添加第三方插件..."

# 基础插件
git_clone https://github.com/kongfl888/luci-app-adguardhome
git_clone https://github.com/sirpdboy/luci-app-ddns-go
git_clone_all https://github.com/sbwml/luci-app-alist
git_clone_all https://github.com/sbwml/luci-app-mosdns
git_clone https://github.com/sbwml/packages_lang_golang golang
git_clone_all https://github.com/linkease/istore-ui
git_clone_all https://github.com/linkease/istore luci
git_clone_all https://github.com/brvphoenix/luci-app-wrtbwmon
git_clone_all https://github.com/brvphoenix/wrtbwmon

# 科学上网（仅保留 OpenClash；HomeProxy 来自官方 feeds，会自动拉取 sing-box 后端）
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash

# VPN相关
git_clone https://github.com/esirplayground/luci-app-poweroff
git_clone -b openwrt-18.06 https://github.com/tty228/luci-app-wechatpush luci-app-serverchan

# Tailscale VPN（图形界面 + 后端）
git_clone https://github.com/asvow/luci-app-tailscale
# 删除官方 tailscale 包自带的 init.d/config，由 luci-app-tailscale 接管
TAILSCALE_MK="feeds/packages/net/tailscale/Makefile"
if [ -f "$TAILSCALE_MK" ]; then
    sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' "$TAILSCALE_MK"
    echo "  ✅ 清理官方 tailscale init.d/config"
fi

# VNT 虚拟组网（ucode 版，多实例 + 在线更新 + 防火墙自动放行）
git_clone https://github.com/whzhni1/luci-app-vnt2

# ============ 用户追加功能源 ============
# 腾讯云 DDNS (luci-app-tencentddns)
git_clone https://github.com/Tencent-Cloud-Plugins/tencentcloud-openwrt-plugin-ddns
# 将 tencentddns 菜单从 admin/tencentcloud 归位到 admin/services
tencentddns_ctrl="package/tencentcloud-openwrt-plugin-ddns/tencentcloud_ddns/files/luci/controller/tencentddns.lua"
if [ -f "$tencentddns_ctrl" ]; then
    sed -i 's/{"admin", "tencentcloud"}/{"admin", "services", "tencentcloud"}/g' "$tencentddns_ctrl"
    sed -i 's/"腾讯云设置", 30/"腾讯云设置", 90/g' "$tencentddns_ctrl"
    echo "  ✅ tencentddns 菜单归位到服务"
fi
# NPC 内网穿透客户端 (luci-app-npc + npc)
git_clone https://github.com/goodmen001/nps-openwrt
# EasyTier 去中心化组网 (luci-app-easytier)
git_clone https://github.com/EasyTier/luci-app-easytier
# rtp2httpd IPTV 组播转单播 (luci-app-rtp2httpd + rtp2httpd)
# 注意: 其 Makefile 用 $(CURDIR)/../../* 拷贝整个仓库源码，
# 必须保持 package/rtp2httpd/openwrt-support/... 的相对路径结构，不能拆开拷贝
git_clone https://github.com/stackia/rtp2httpd

# 主题（仅 Aurora）
git_clone https://github.com/eamonxg/luci-theme-aurora
git_clone https://github.com/eamonxg/luci-app-aurora-config

# ------------------------------------------------------------
# 5. 修复 Makefile 路径（适配官方 feeds 结构）
# ------------------------------------------------------------
find package/*/ -maxdepth 2 -path "*/Makefile" 2>/dev/null | while IFS= read -r f; do
    sed -i 's|\.\./\.\./luci\.mk|$(TOPDIR)/feeds/luci/luci.mk|g' "$f"
    sed -i 's|\.\./\.\./lang/golang/golang-package\.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' "$f"
    sed -i 's|PKG_SOURCE_URL:=@GHREPO|PKG_SOURCE_URL:=https://github.com|g' "$f"
    sed -i 's|PKG_SOURCE_URL:=@GHCODELOAD|PKG_SOURCE_URL:=https://codeload.github.com|g' "$f"
done

# 转换插件语言翻译（zh-cn / zh_Hans 软链兼容）
for e in $(ls -d package/luci-*/po 2>/dev/null) $(ls -d feeds/luci/applications/luci-*/po 2>/dev/null); do
    if [[ -d "$e/zh-cn" && ! -d "$e/zh_Hans" ]]; then
        ln -s zh-cn "$e/zh_Hans" 2>/dev/null || true
    elif [[ -d "$e/zh_Hans" && ! -d "$e/zh-cn" ]]; then
        ln -s zh_Hans "$e/zh-cn" 2>/dev/null || true
    fi
done

# ------------------------------------------------------------
# 6. 取消主题默认设置
# ------------------------------------------------------------
find package/luci-theme-*/* -type f -name '*luci-theme-*' -print 2>/dev/null | while IFS= read -r f; do
    sed -i '/set luci.main.mediaurlbase/d' "$f"
done

# ------------------------------------------------------------
# 7. 修复 xfsprogs 编译
# ------------------------------------------------------------
XFSPROGS_MAKEFILE="feeds/packages/utils/xfsprogs/Makefile"
if [ -f "$XFSPROGS_MAKEFILE" ]; then
    sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' "$XFSPROGS_MAKEFILE"
fi

# ------------------------------------------------------------
# 8. 修复 frp npm ENOTEMPTY 并行竞态
# ------------------------------------------------------------
FRP_MAKEFILE="feeds/packages/net/frp/Makefile"
if [ -f "$FRP_MAKEFILE" ]; then
    sed -i '/^include $(INCLUDE_DIR)\/package.mk/a PKG_BUILD_PARALLEL:=0' "$FRP_MAKEFILE"
    sed -i 's/npm install /npm install --force --prefer-offline /g' "$FRP_MAKEFILE"
fi

# ------------------------------------------------------------
# 9. 设置默认主题为 Aurora
# ------------------------------------------------------------
sed -i "s|mediaurlbase=.*|mediaurlbase='/luci-static/aurora'|" package/base-files/files/etc/config/luci 2>/dev/null || \
echo "config core 'main'" > package/base-files/files/etc/config/luci && \
echo "    option mediaurlbase '/luci-static/aurora'" >> package/base-files/files/etc/config/luci

# ------------------------------------------------------------
# 10. 更新 feeds
# ------------------------------------------------------------
./scripts/feeds update -a
./scripts/feeds install -a

# ------------------------------------------------------------
# 11. 禁用有问题的包（kmod-oaf 在 ImmortalWrt master 上可能不存在）
# ------------------------------------------------------------
sed -i 's/CONFIG_PACKAGE_kmod-oaf=y/# CONFIG_PACKAGE_kmod-oaf is not set/g' .config 2>/dev/null || true
sed -i 's/CONFIG_PACKAGE_luci-app-oaf=y/# CONFIG_PACKAGE_luci-app-oaf is not set/g' .config 2>/dev/null || true

echo ""
echo "========================================"
echo "✅ DIY 脚本执行完成"
echo "========================================"
# ------------------------------------------------------------
# 13. 修复 apk install 文件覆盖冲突
#
#   冲突1: luci-app-mosdns (sbwml克隆版) 的 Makefile 把 scripts/openwrt/mosdns-init
#   安装为 /etc/init.d/mosdns，与官方 mosdns 后端包冲突：
#     ERROR: luci-app-mosdns-1.7.14-r1: trying to overwrite etc/init.d/mosdns
#     owned by mosdns-5.3.3-r1.
#   修法：删掉 sbwml 源码目录里的 init.d 源文件（后端 mosdns 包已提供）。
#
#   冲突2: luci-app-openvpn-server 的 Makefile 写了 /etc/config/openvpn，
#   与 openvpn-openssl 的同一文件冲突：
#     ERROR: luci-app-openvpn-server-3.0-r0: trying to overwrite etc/config/openvpn
#     owned by openvpn-openssl-2.7.6-r1.
#   修法：删掉 feeds/luci 里的 config/openvpn 源文件（openvpn-openssl 已提供）。
# ------------------------------------------------------------

# 修复 mosdns：删掉 sbwml 版 luci-app-mosdns 源码里的 init.d/mosdns 源文件
if [ -f "package/luci-app-mosdns/root/etc/init.d/mosdns" ]; then
    rm -f "package/luci-app-mosdns/root/etc/init.d/mosdns"
    echo "  ✅ 移除 luci-app-mosdns 的重复 etc/init.d/mosdns"
fi

# 修复 openvpn-server：删掉 feeds/luci 里的 etc/config/openvpn 源文件
if [ -f "feeds/luci/applications/luci-app-openvpn-server/root/etc/config/openvpn" ]; then
    rm -f "feeds/luci/applications/luci-app-openvpn-server/root/etc/config/openvpn"
    echo "  ✅ 移除 luci-app-openvpn-server 的重复 etc/config/openvpn"
fi
