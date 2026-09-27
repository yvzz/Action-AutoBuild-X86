#!/usr/bin/env bash
# ============================================================
# 集中式 CI 脚本（借鉴 build-openwrt-003 的 ops.sh 设计）
#   - workflow 只做薄壳：run: scripts/ci/ops.sh <cmd>
#   - 逻辑集中、可本地跑、可 bash -n 校验
# 用法: scripts/ci/ops.sh <command> [args]
# ============================================================
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cmd="${1:-}"
shift || true

log() { printf '[ci] %s\n' "$*"; }
die() { printf '[ci][error] %s\n' "$*" >&2; exit 1; }

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"; elif command -v sudo >/dev/null 2>&1; then sudo "$@"; else "$@"; fi
}

write_env() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then printf '%s=%s\n' "$key" "$value" >> "$GITHUB_ENV"; fi
  export "$key=$value"
}

# 分支标签 -> ImmortalWrt 上游分支
src_ref() {
  case "$1" in
    v24.10) echo "openwrt-24.10" ;;
    v25.12) echo "openwrt-25.12" ;;
    *)      echo "$1" ;;
  esac
}

# ------------------------------------------------------------
# check-token: 前置校验（早失败，别等编译完才发现没令牌）
# ------------------------------------------------------------
check_token() {
  if [[ -n "${GITHUB_TOKEN:-${REPO_TOKEN:-}}" ]]; then
    log "token 校验通过"
  else
    # 编译本身不依赖 token；仅 Release 发布需要。改为告警不阻断，
    # 便于测试工作流继续跑编译、定位是否真缺 token。
    log "⚠️ 未检测到 GITHUB_TOKEN / REPO_TOKEN：影响 Release 发布，不影响编译"
  fi
}

# ------------------------------------------------------------
# load-context <分支标签>   （需 PROFILE 环境变量）
# ------------------------------------------------------------
load_context() {
  local label="${1:?usage: load-context <v24.10|v25.12>}"
  local profile="${PROFILE:?需要 PROFILE 环境变量（Plus / Plus+Docker）}"
  local ref; ref="$(src_ref "$label")"
  local cfg="$repo_root/configs/x86_64_${profile}.config"
  [[ -f "$cfg" ]] || die "找不到配置文件: $cfg"

  write_env REPO_URL "https://github.com/immortalwrt/immortalwrt"
  write_env REPO_BRANCH "$ref"
  write_env BRANCH_LABEL "$label"
  write_env CONFIG_FILE "$cfg"
  write_env TARGET_PROFILE "$profile"
  write_env OPENWRT_PATH "${OPENWRT_PATH:-${GITHUB_WORKSPACE:-$PWD}/openwrt}"
  write_env LAN_IP "${LAN_IP:-${DEFAULT_IP:-10.0.0.252}}"

  log "context: label=$label ref=$ref profile=$profile"
  log "         config=$cfg"
  log "         openwrt=$OPENWRT_PATH lan_ip=$LAN_IP"
}

# ------------------------------------------------------------
# bootstrap: 安装编译依赖 + ccache
# ------------------------------------------------------------
bootstrap() {
  log "安装编译依赖"
  as_root apt-get -qq update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get -qq install -y \
    aria2 autoconf automake binutils bison bzip2 ccache clang cmake cpio \
    curl device-tree-compiler flex gawk gcc git gperf help2man libelf-dev \
    libglib2.0-dev libtool liblzma-dev libncurses-dev libssl-dev lz4 m4 \
    make mercurial genisoimage msmtp ninja-build p7zip-full patch pkgconf \
    python3 python3-dev python3-pip python3-setuptools rsync squashfs-tools \
    texinfo upx-ucl unzip uuid-dev vim wget xxd zlib1g-dev
  mkdir -p "$HOME/.ccache"
  ccache -M 5G >/dev/null 2>&1 || true
  log "依赖安装完成（ccache 5G）"
}

# ------------------------------------------------------------
# cleanup-disk: 纯脚本释放磁盘（不依赖第三方 action）
# ------------------------------------------------------------
cleanup_disk() {
  log "释放 runner 磁盘空间"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get -y purge --auto-remove \
    'azure-cli' 'google-cloud-cli' 'microsoft-edge-stable' 'google-chrome-stable' \
    'firefox' 'postgresql*' 'temurin-*' '*llvm*' 'mysql*' 'dotnet-sdk-*' || true
  as_root rm -rf /usr/share/swift /usr/share/miniconda /usr/share/az* /usr/share/glade* \
    /usr/local/lib/node_modules /usr/local/share/chromium /usr/local/share/powershell \
    /usr/local/.ghcup /opt/ghc /swapfile || true
  as_root swapoff -a || true
  as_root apt-get -qq clean || true
  as_root rm -rf /var/lib/apt/lists/* || true
  log "磁盘释放完成"
}

# ------------------------------------------------------------
# prepare-openwrt <openwrt-root>
#   应用顺序: config -> files -> patches -> diy.sh -> presets -> init-settings -> defconfig
# ------------------------------------------------------------
prepare_openwrt() {
  local openwrt_root="${1:?usage: prepare-openwrt <openwrt-root>}"
  [[ -d "$openwrt_root" ]] || die "源码目录不存在: $openwrt_root"
  [[ -n "${CONFIG_FILE:-}" ]] || die "CONFIG_FILE 未设置（先跑 load-context）"

  log "应用配置文件: $CONFIG_FILE"
  cp -f "$CONFIG_FILE" "$openwrt_root/.config"

  if [[ -d "$repo_root/files" ]]; then
    mkdir -p "$openwrt_root/files"
    rsync -a --exclude 'README*' "$repo_root/files/" "$openwrt_root/files/"
    log "files 覆盖层已应用"
  fi

  if [[ -d "$repo_root/patches" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      patch -d "$openwrt_root" -p1 < "$p"
    done < <(find "$repo_root/patches" -type f \( -name '*.patch' -o -name '*.diff' \) | sort)
    log "补丁已应用"
  fi

  log "执行 diy.sh"
  ( cd "$openwrt_root" && GITHUB_WORKSPACE="$repo_root" bash "$repo_root/scripts/diy.sh" )

  local s
  for s in preset-clash-core preset-adguard-core preset-terminal-tools; do
    if [[ -f "$repo_root/scripts/$s.sh" ]]; then
      log "执行 $s.sh"
      ( cd "$openwrt_root" && GITHUB_WORKSPACE="$repo_root" bash "$repo_root/scripts/$s.sh" ) || log "⚠️ $s.sh 返回非零，继续"
    fi
  done

  # 首启设置写进 uci-defaults，并注入 LAN IP
  if [[ -f "$repo_root/scripts/init-settings.sh" ]]; then
    mkdir -p "$openwrt_root/files/etc/uci-defaults"
    cp -f "$repo_root/scripts/init-settings.sh" "$openwrt_root/files/etc/uci-defaults/99-init-settings"
    if [[ -n "${LAN_IP:-}" ]]; then
      sed -i "s#\(ipaddr=\).*#\1'$LAN_IP'#; s#\(netmask=\).*#\1'255.255.255.0'#" \
        "$openwrt_root/files/etc/uci-defaults/99-init-settings"
      log "首启设置已注入 LAN IP=$LAN_IP"
    fi
  fi

  if [[ -x "$openwrt_root/scripts/feeds" ]]; then
    ( cd "$openwrt_root" && ./scripts/feeds update -a && ./scripts/feeds install -a )
    log "feeds 已更新/安装"
  fi

  ( cd "$openwrt_root" && make defconfig )
  log "defconfig 完成"
}

# ------------------------------------------------------------
# finalize-firmware <openwrt-root>
#   按 clear.list 裁剪产物 + 保存 built.config + 打包 ipk + 重算 sha256sums
# ------------------------------------------------------------
finalize_firmware() {
  local openwrt_root="${1:?usage: finalize-firmware <openwrt-root>}"
  local targets="$openwrt_root/bin/targets"
  [[ -d "$targets" ]] || die "未找到产物目录: $targets"

  local out_dir
  out_dir="$(find "$targets" -mindepth 2 -maxdepth 2 -type d | head -n1 || true)"
  [[ -n "$out_dir" ]] || die "未找到 target/subtarget 目录"
  cd "$out_dir"

  local clear_file="$repo_root/scripts/ci/clear.list"
  if [[ -f "$clear_file" ]]; then
    while IFS= read -r pat; do
      [[ -n "$pat" ]] || continue
      case "$pat" in \#*) continue ;; esac
      find . -maxdepth 1 -name "$pat" -exec rm -rf {} + 2>/dev/null || true
    done < "$clear_file"
    log "clear.list 裁剪完成"
  fi

  cp -f "$openwrt_root/.config" built.config

  mkdir -p packages
  find "$openwrt_root/bin/packages" \( -name '*.ipk' -o -name '*.apk' \) -exec cp {} packages/ \; 2>/dev/null || true
  if [[ -n "$(ls -A packages 2>/dev/null || true)" ]]; then
    tar -czf packages.tar.gz packages/
    rm -rf packages
  else
    rmdir packages 2>/dev/null || true
  fi

  # 内核版本
  local kver
  kver="$(ls "$openwrt_root"/dl/linux-*.tar.* 2>/dev/null | sed -E 's#.*/linux-([0-9]+\.[0-9]+\.[0-9]+).*#\1#' | sort -V | tail -1 || true)"
  if [[ -z "$kver" ]]; then
    kver="$(grep -oE '^LINUX_VERSION-[0-9.]+' "$openwrt_root/include/kernel-version.mk" 2>/dev/null | tail -1 | sed 's/LINUX_VERSION-//' || true)"
  fi
  kver="${kver:-unknown}"
  write_env KERNEL_VERSION "$kver"

  # sha256sums：只对当前层文件，避免把子目录当文件报错
  rm -f sha256sums
  find . -maxdepth 1 -type f ! -name 'sha256sums' -print0 | xargs -0 -r sha256sum > sha256sums

  log "产物整理完成（内核 $kver）"
  ls -lh | sed 's/^/[ci]   /'
}

# ------------------------------------------------------------
# notice [stage]: 通知（默认仅打日志；如需 TG/Pushplus 自行加密钥）
# ------------------------------------------------------------
notice() {
  local stage="${1:-notice}"
  log "[${TARGET_PROFILE:-unknown}] ${stage}: branch=${BRANCH_LABEL:-} ref=${REPO_BRANCH:-} config=${CONFIG_FILE:-}"
}

# ------------------------------------------------------------
# upload-release <tag> <dir>   使用内置 GITHUB_TOKEN（无需高权限 PAT）
# ------------------------------------------------------------
upload_release() {
  local tag="${1:?usage: upload-release <tag> <dir>}"
  local dir="${2:?usage: upload-release <tag> <dir>}"
  local token="${GITHUB_TOKEN:-${REPO_TOKEN:-}}"
  if [[ -z "$token" ]]; then
    log "⚠️ 缺少 GITHUB_TOKEN，跳过 Release 发布（编译产物仍在 Artifact 中）"
    return 0
  fi
  [[ -d "$dir" ]] || die "上传目录不存在: $dir"

  local api="https://api.github.com/repos/${GITHUB_REPOSITORY}"
  local auth=(-H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

  local release
  if ! release="$(curl -fsSL "${auth[@]}" "$api/releases/tags/$tag" 2>/dev/null)"; then
    local payload
    payload="$(jq -n --arg tag "$tag" --arg target "${GITHUB_REF_NAME:-main}" \
      '{tag_name:$tag,name:$tag,target_commitish:$target,draft:false,prerelease:false}')"
    release="$(curl -fsSL -X POST "${auth[@]}" -d "$payload" "$api/releases")"
    log "已创建 Release: $tag"
  fi

  local rid upload_url
  rid="$(jq -r '.id' <<<"$release")"
  upload_url="$(jq -r '.upload_url' <<<"$release" | sed 's/{.*//')"

  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -type f ! -path '*/packages/*' \
    \( -name '*.tar.gz' -o -name '*.img.gz' -o -name '*.img' -o -name '*.bin' -o -name '*.efi' \
       -o -name '*.manifest' -o -name 'built.config' -o -name 'sha256sums' \) | sort)
  [[ "${#files[@]}" -gt 0 ]] || die "未找到可上传文件: $dir"

  local assets
  assets="$(curl -fsSL "${auth[@]}" "$api/releases/$rid/assets")"

  local f base enc aid
  for f in "${files[@]}"; do
    base="$(basename "$f")"
    enc="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$base")"
    aid="$(jq -r --arg n "$base" '.[] | select(.name==$n) | .id' <<<"$assets" | head -n1)"
    if [[ -n "${aid:-}" && "$aid" != "null" ]]; then
      curl -fsSL -X DELETE "${auth[@]}" "$api/releases/assets/$aid" >/dev/null || true
    fi
    curl -fsSL -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @"$f" \
      "${upload_url}?name=${enc}" >/dev/null
    log "已上传 $base -> Release $tag"
  done
}

case "$cmd" in
  check-token)      check_token ;;
  load-context)     load_context "${1:?usage: load-context <label>}" ;;
  bootstrap)        bootstrap ;;
  cleanup-disk)     cleanup_disk ;;
  prepare-openwrt)  prepare_openwrt "${1:?usage: prepare-openwrt <openwrt-root>}" ;;
  finalize-firmware) finalize_firmware "${1:?usage: finalize-firmware <openwrt-root>}" ;;
  notice)           notice "${1:-notice}" ;;
  upload-release)   upload_release "${1:?usage: upload-release <tag> <dir>}" "${2:?usage: upload-release <tag> <dir>}" ;;
  *)
    cat >&2 <<EOF
usage: $0 <command> [args]
commands:
  check-token
  load-context <v24.10|v25.12>      (env: PROFILE)
  bootstrap
  cleanup-disk
  prepare-openwrt <openwrt-root>
  finalize-firmware <openwrt-root>
  notice [stage]
  upload-release <tag> <dir>
EOF
    exit 1 ;;
esac
