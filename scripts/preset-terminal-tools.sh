#!/bin/bash
# ============================================================
# 配置 ZSH 终端环境（oh-my-zsh + 插件）
# ============================================================
set -euo pipefail

OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"

[ -d "$OPENWRT_PATH/files/root" ] || mkdir -p "$OPENWRT_PATH/files/root"

# Clone oh-my-zsh
git clone -q https://github.com/ohmyzsh/ohmyzsh "$OPENWRT_PATH/files/root/.oh-my-zsh"

# Install extra plugins
git clone -q https://github.com/zsh-users/zsh-autosuggestions "$OPENWRT_PATH/files/root/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
git clone -q https://github.com/zsh-users/zsh-syntax-highlighting "$OPENWRT_PATH/files/root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
git clone -q https://github.com/zsh-users/zsh-completions "$OPENWRT_PATH/files/root/.oh-my-zsh/custom/plugins/zsh-completions"

# Copy .zshrc
cp "$GITHUB_WORKSPACE/scripts/.zshrc" "$OPENWRT_PATH/files/root"

echo "✅ ZSH 终端工具配置完成"