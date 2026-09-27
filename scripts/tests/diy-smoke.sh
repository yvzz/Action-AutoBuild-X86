#!/usr/bin/env bash
# ============================================================
# 编译前冒烟测试（借鉴 build-openwrt-003 的 diy-part smoke 思路）
#   1) 语法校验所有脚本
#   2) 在沙箱里用 stub git/feeds 跑一遍 scripts/diy.sh，断言关键改动生效
#   3) 静态断言：脚本/配置里的关键不变量
# 不联网、秒级完成；失败即退出，避免白跑几小时编译
# ============================================================
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/scripts/diy.sh"
fail=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=1; }

echo "== 1. 语法校验 =="
for f in "$repo_root"/scripts/*.sh "$repo_root"/scripts/ci/*.sh "$repo_root"/scripts/tests/*.sh; do
  [[ -f "$f" ]] || continue
  if bash -n "$f" 2>/dev/null; then ok "bash -n $(basename "$f")"; else bad "语法错误: $f"; fi
done

echo "== 2. 沙箱运行 diy.sh =="

# --- stub git：模拟 clone 成功并生成最小目录结构 ---
git() {
  case "${1:-}" in
    clone)
      local dest="${!#}"
      mkdir -p "$dest/po/zh-cn" "$dest/subpkg"
      printf 'include ../../luci.mk\nPKG_SOURCE_URL:=@GHREPO\n' > "$dest/Makefile"
      printf '#include <x.h>\n' > "$dest/po/zh-cn/x.po"
      printf 'include $(TOPDIR)/rules.mk\n' > "$dest/subpkg/Makefile"
      return 0 ;;
    sparse-checkout)
      shift
      local p
      for p in "$@"; do mkdir -p "$p"; printf 'include $(TOPDIR)/rules.mk\n' > "$p/Makefile"; done
      return 0 ;;
    *) return 0 ;;
  esac
}
export -f git

sb="$(mktemp -d)"
trap 'rm -rf "$sb" /tmp/sparse-clone' EXIT

# --- sed 兼容层：macOS/BSD 下把 GNU 风格 `sed -i` / `a 文本` 转成 BSD 写法（CI 为 Linux 时直接透传）---
mkdir -p "$sb/bin"
cat > "$sb/bin/sed" <<'SH'
#!/usr/bin/env bash
if [[ "$(uname)" != "Darwin" ]]; then exec /usr/bin/sed "$@"; fi
fix() {
  local s="$1"
  if [[ "$s" == /* && "$s" =~ ^(/.+/)([aic])[[:space:]]+(.+)$ ]]; then
    printf '%s%s\\\n%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  else
    printf '%s' "$s"
  fi
}
args=(); expect=0
for a in "$@"; do
  if (( expect )); then args+=("$(fix "$a")"); expect=0; continue; fi
  case "$a" in
    -i)   args+=(-i ''); expect=1 ;;
    -i*)  args+=("${a}''"); expect=1 ;;
    *)    args+=("$a") ;;
  esac
done
exec /usr/bin/sed "${args[@]}"
SH
chmod +x "$sb/bin/sed"
export PATH="$sb/bin:$PATH"

# --- 造 fixture ---
mkdir -p "$sb/images" "$sb/scripts" "$sb/openwrt"
cp -f "$script" "$sb/scripts/diy.sh"
printf 'dummy-image\n' > "$sb/images/bg1.jpg"

ow="$sb/openwrt"
mkdir -p "$ow/package/base-files/files/bin" \
         "$ow/package/base-files/files/etc/config" \
         "$ow/package/luci-theme-argon/htdocs/luci-static/argon/img" \
         "$ow/package/luci-app-passwall2" \
         "$ow/feeds/packages/utils/ttyd/files" \
         "$ow/feeds/packages/utils/xfsprogs" \
         "$ow/feeds/packages/net/frp" \
         "$ow/scripts"
printf '#!/bin/sh\nlan_ip=192.168.1.1\n' > "$ow/package/base-files/files/bin/config_generate"
printf 'root:::0:99999:7:::\n'          > "$ow/package/base-files/files/etc/shadow"
printf "config core 'main'\n\toption mediaurlbase '/luci-static/bootstrap'\n" > "$ow/package/base-files/files/etc/config/luci"
printf 'include $(TOPDIR)/rules.mk\nPKG_SOURCE_URL:=@GHREPO\n\tselect PACKAGE_iptables-nft\n\tselect PACKAGE_iptables-zz-legacy\n' > "$ow/package/luci-app-passwall2/Makefile"
printf '/bin/login\n'                    > "$ow/feeds/packages/utils/ttyd/files/ttyd.config"
printf 'include $(TOPDIR)/package.mk\n'  > "$ow/feeds/packages/utils/xfsprogs/Makefile"
printf 'include $(TOPDIR)/package.mk\n'  > "$ow/feeds/packages/net/frp/Makefile"
printf 'CONFIG_PACKAGE_kmod-oaf=y\n'     > "$ow/.config"
printf '#!/bin/sh\nexit 0\n'             > "$ow/scripts/feeds"
chmod +x "$ow/scripts/feeds"

# --- 运行 ---
if ( cd "$ow" && GITHUB_WORKSPACE="$sb" bash "$sb/scripts/diy.sh" >/dev/null 2>"$sb/err.log" ); then
  ok "diy.sh 在沙箱中执行成功"
else
  bad "diy.sh 执行失败:"; sed 's/^/      /' "$sb/err.log" | tail -20
fi

# --- 断言 ---
chk()  { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }
nchk() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$desc"; else ok "$desc"; fi; }

chk  "默认 IP 改为 10.0.0.252"        grep -q "10.0.0.252" "$ow/package/base-files/files/bin/config_generate"
nchk "旧 IP 192.168.1.1 已清除"        grep -q "192.168.1.1" "$ow/package/base-files/files/bin/config_generate"
chk  "root 密码已写入 shadow"          grep -q 'root:\$1\$V4UetPzk\$' "$ow/package/base-files/files/etc/shadow"
chk  "ttyd 免登录"                     grep -q "/bin/login -f root" "$ow/feeds/packages/utils/ttyd/files/ttyd.config"
chk  "默认主题 = argon"                grep -q "luci-static/argon" "$ow/package/base-files/files/etc/config/luci"
nchk "passwall select 冲突已移除"      grep -q "iptables-zz-legacy" "$ow/package/luci-app-passwall2/Makefile"
chk  "luci 翻译软链 zh_Hans"           test -L "$ow/package/luci-theme-argon/po/zh_Hans"
chk  "luci.mk 路径修复"                grep -q 'feeds/luci/luci.mk' "$ow/package/luci-theme-argon/Makefile"
chk  "GHREPO 短链替换"                 grep -q 'PKG_SOURCE_URL:=https://github.com' "$ow/package/luci-theme-argon/Makefile"
chk  "kmod-oaf 已禁用"                 grep -q '^# CONFIG_PACKAGE_kmod-oaf is not set' "$ow/.config"

echo "== 3. 静态不变量 =="
chk "diy.sh 含默认 IP 10.0.0.252"       grep -q "10.0.0.252" "$script"
chk "diy.sh 含 passwall select 修复"    grep -q "iptables-zz-legacy" "$script"
chk "diy.sh 整仓克隆 rtp2httpd"          grep -q "stackia/rtp2httpd" "$script"
chk "runtime 分支映射含 openwrt-25.12"  grep -q "openwrt-25.12" "$repo_root/.github/workflows/schedule-build.yml"
for cfg in "$repo_root"/configs/*.config; do
  chk "$(basename "$cfg") 目标 x86_64"   grep -q '^CONFIG_TARGET_x86_64=y' "$cfg"
  chk "$(basename "$cfg") 含 passwall2"  grep -q '^CONFIG_PACKAGE_luci-app-passwall2=y' "$cfg"
done

echo
if [[ "$fail" -eq 0 ]]; then
  printf '\033[32m冒烟测试通过 ✅\033[0m\n'
else
  printf '\033[31m冒烟测试失败 ❌\033[0m\n'; exit 1
fi
