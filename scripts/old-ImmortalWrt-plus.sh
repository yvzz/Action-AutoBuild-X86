#!/bin/bash

# ============================================================
# ImmortalWrt 源码适配版
# ImmortalWrt 基于 OpenWrt，添加了更多内核模块和软件包
# ============================================================

# 修改默认IP
sed -i 's/192.168.1.1/10.0.0.252/g' package/base-files/files/bin/config_generate

# TTYD 免登录
# sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 移除官方 OpenWrt 不存在的旧包目录（feeds 里没有）
# rm -rf feeds/packages/net/msd_lite  # 官方 OpenWrt 没有 msd_lite

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# ============================================================
# 添加额外插件（第三方）
# ============================================================

# Server酱微信推送
git clone --depth=1 -b openwrt-18.06 https://github.com/tty228/luci-app-wechatpush package/luci-app-serverchan

# 关机按钮
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff

# 应用过滤（OpenAppFilter）
git clone --depth=1 https://github.com/destan19/OpenAppFilter package/OpenAppFilter

# EQoS 简易限速
git_sparse_clone openwrt-18.06 https://github.com/immortalwrt/luci applications/luci-app-eqos

# Passwall2（科学上网）
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall2 package/luci-app-passwall2

# OpenClash
git_sparse_clone master https://github.com/vernesong/OpenClash luci-app-openclash


# Argon 主题（jerrykuku 版）
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# Aurora 主题
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config package/luci-app-aurora-config

# 更改 Argon 主题背景
cp -f $GITHUB_WORKSPACE/images/bg1.jpg package/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# ============================================================
# 其他功能
# ============================================================

# DDNS.to — 预编译二进制下载经常 404，已禁用
# git_sparse_clone main https://github.com/linkease/nas-packages-luci luci/luci-app-ddnsto
# git_sparse_clone master https://github.com/linkease/nas-packages network/services/ddnsto

# iStore 应用商店
git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
git_sparse_clone main https://github.com/linkease/istore luci

# ============================================================
# 修复与适配
# ============================================================

# 修复 hostapd 报错 — patch 文件缺失，已禁用
# cp -f $GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch

# 修复 xfsprogs 编译（armv8）
sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile

# 修改 Makefile 路径（适配官方 OpenWrt feeds 结构）
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


# 禁用有问题的包
# ============================================================

# ImmortalWrt 有 kmod-oaf 支持，如编译失败再禁
sed -i 's/CONFIG_PACKAGE_kmod-oaf=y/# CONFIG_PACKAGE_kmod-oaf is not set/g' .config
sed -i 's/CONFIG_PACKAGE_luci-app-oaf=y/# CONFIG_PACKAGE_luci-app-oaf is not set/g' .config
sed -i 's/CONFIG_PACKAGE_kmod-oaf=m/# CONFIG_PACKAGE_kmod-oaf is not set/g' .config
sed -i 's/CONFIG_PACKAGE_luci-app-oaf=m/# CONFIG_PACKAGE_luci-app-oaf is not set/g' .config
