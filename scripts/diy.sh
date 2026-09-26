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

# 科学上网
git_clone_all https://github.com/Openwrt-Passwall/openwrt-passwall-packages
git_clone_all https://github.com/Openwrt-Passwall/openwrt-passwall
git_clone_all https://github.com/Openwrt-Passwall/openwrt-passwall2
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash
git_clone_all https://github.com/nikkinikki-org/OpenWrt-nikki
git_clone_all https://github.com/nikkinikki-org/OpenWrt-momo

# VPN相关
git_clone https://github.com/esirplayground/luci-app-poweroff
git_clone -b openwrt-18.06 https://github.com/tty228/luci-app-wechatpush luci-app-serverchan

# 主题
git_clone https://github.com/jerrykuku/luci-theme-argon
git_clone https://github.com/jerrykuku/luci-app-argon-config
git_clone https://github.com/eamonxg/luci-theme-aurora
git_clone https://github.com/eamonxg/luci-app-aurora-config
git_clone https://github.com/sirpdboy/luci-theme-kucat
git_clone https://github.com/sirpdboy/luci-app-kucat-config

# 更改 Argon 主题背景
cp -f "$GITHUB_WORKSPACE/images/bg1.jpg" package/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

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
# 9. 设置默认主题为 Argon
# ------------------------------------------------------------
sed -i "s|mediaurlbase=.*|mediaurlbase='/luci-static/argon'|" package/base-files/files/etc/config/luci 2>/dev/null || \
echo "config core 'main'" > package/base-files/files/etc/config/luci && \
echo "    option mediaurlbase '/luci-static/argon'" >> package/base-files/files/etc/config/luci

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