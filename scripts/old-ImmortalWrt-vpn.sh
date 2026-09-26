#!/bin/bash

# ============================================================
# ImmortalWrt 源码适配版 — VPN 版本
# ImmortalWrt 基于 OpenWrt，添加了更多内核模块和软件包
# ============================================================

# 修改默认IP（ImmortalWrt 默认 192.168.1.1）
sed -i 's/192.168.1.1/10.0.0.252/g' package/base-files/files/bin/config_generate

# Git稀疏克隆
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# ============================================================
# 第三方插件
# ============================================================

# 科学上网
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall2 package/luci-app-passwall2
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash

# Netdata 监控
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata

# AdGuardHome
git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome package/luci-app-adguardhome

# Server酱推送
git clone --depth=1 -b openwrt-18.06 https://github.com/tty228/luci-app-wechatpush package/luci-app-serverchan

# 关机按钮
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff

# msd_lite
git clone --depth=1 https://github.com/ximiTech/luci-app-msd_lite package/luci-app-msd_lite
git clone --depth=1 https://github.com/ximiTech/msd_lite package/msd_lite

# ============================================================
# 主题
# ============================================================

git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config package/luci-app-aurora-config

cp -f $GITHUB_WORKSPACE/images/bg1.jpg package/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# ============================================================
# 其他功能
# ============================================================

# iStore
git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
git_sparse_clone main https://github.com/linkease/istore luci

# ============================================================
# 修复与适配
# ============================================================

# hostapd patch 缺失，已禁用
# cp -f $GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch

# 修复 xfsprogs 编译
sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile

# 修改 Makefile 路径
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/..\/..\/lang\/golang\/golang-package.mk/$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang-package.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {}

# 取消主题默认设置
find package/luci-theme-*/* -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

# ============================================================
# 更新 feeds
# ============================================================

./scripts/feeds update -a
./scripts/feeds install -a

# 修复 frp npm ENOTEMPTY 并行竞态
if [ -f feeds/packages/net/frp/Makefile ]; then
  sed -i '/^include $(INCLUDE_DIR)\/package.mk/a PKG_BUILD_PARALLEL:=0' feeds/packages/net/frp/Makefile
  sed -i 's/npm install /npm install --force --prefer-offline /g' feeds/packages/net/frp/Makefile
fi
