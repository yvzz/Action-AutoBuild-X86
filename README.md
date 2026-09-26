# ImmortalWrt X86_64 云编译

基于 GitHub Actions 的 ImmortalWrt X86_64 固件自动编译方案。

## ✨ 特性

- **双分支支持**：ImmortalWrt `openwrt-24.10`（稳定）和 `master`（滚动）
- **三个配置**：Plus（全能）、Plus+Docker（含 Docker）、VPN（全 VPN 栈）
- **智能调度**：每周六 00:00 北京时间自动检测源码更新，有更新才编译
- **增量编译**：cachewrtbuild 工具链缓存，省 15-30 分钟
- **工程化脚本**：融合 DSL 式插件管理 + 透明依赖安装

## 📋 固件信息

| 项目 | 值 |
|------|------|
| 平台架构 | x86_64 |
| 固件源码 | immortalwrt/immortalwrt |
| 默认地址 | 10.0.0.252 |
| 默认密码 | password |
| 默认主题 | Argon |

## 🔧 配置说明

| 配置 | 说明 |
|------|------|
| `Plus` | 全功能固件：科学上网 + NAS + 下载 + 监控 + 广告过滤 |
| `Plus+Docker` | Plus 基础上增加 Docker 支持 |
| `VPN` | 全 VPN 栈：OpenVPN/IPsec/PPTP/SoftEther/WireGuard/ZeroTier/N2N |

## 🚀 使用方式

### 自动编译

每周六 00:00（北京时间）自动触发：
1. 检测 ImmortalWrt 两个分支是否有新提交
2. 有更新则触发对应分支的全配置编译（6 个并行任务）
3. 无更新则跳过

### 手动编译

在 GitHub Actions 页面手动触发 `Schedule Build`：
- 选择分支（openwrt-24.10 / master）
- 选择配置（Plus / Plus+Docker / VPN）
- 可选设置 LAN IP

## 📁 仓库结构

```
├── .github/workflows/
│   ├── schedule-build.yml      # 调度 workflow（检测更新 + 触发编译）
│   ├── build-openwrt.yml       # 可复用编译 workflow
│   └── delete-old-workflows.yml # 清理旧 workflow 和 release
├── configs/
│   ├── x86_64_Plus.config
│   ├── x86_64_Plus+Docker.config
│   └── x86_64_VPN.config
├── scripts/
│   ├── diy.sh                  # 自定义脚本（插件管理 + 配置修改）
│   ├── init-settings.sh        # 首次启动设置（IP/时区/语言/主题）
│   ├── preset-clash-core.sh    # OpenClash 内核下载
│   ├── preset-adguard-core.sh  # AdGuardHome 内核下载
│   ├── preset-terminal-tools.sh # ZSH 终端工具
│   └── .zshrc                  # ZSH 配置
└── images/
    └── bg1.jpg                 # Argon 主题背景
```

## 🛡️ 安全

- 依赖安装：YAML 内显式列包，**无短链/无外部脚本**
- 工具链：GitHub Actions Cache 原生集成
- 磁盘：sclsyin/maximize-build-space + disk-space-optimizer