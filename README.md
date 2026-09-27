# ImmortalWrt X86_64 云编译

基于 GitHub Actions 的 ImmortalWrt X86_64 固件自动编译方案。

## ✨ 特性

- **双分支支持**：分支标签 `v24.10`（对应上游 `openwrt-24.10`，稳定）与 `v25.12`（对应上游 `master`，滚动 SNAPSHOT）
- **两个配置**：Plus（主档）、Plus+Docker（含 Docker）
- **智能调度**：每周六 00:00 北京时间自动检测源码更新，有更新才编译
- **增量编译**：cachewrtbuild 工具链缓存，省 15-30 分钟
- **工程化脚本**：融合 DSL 式插件管理 + 透明依赖安装

## 📋 固件信息

| 项目 | 值 |
|------|------|
| 平台架构 | x86_64 |
| 固件源码 | immortalwrt/immortalwrt |
| 分支标签 | `v24.10` → `openwrt-24.10`，`v25.12` → `master` |
| 默认地址 | 10.0.0.252 |
| 默认密码 | password |
| 默认主题 | Argon |

## 🔧 配置说明

| 配置 | 说明 |
|------|------|
| `Plus` | 主固件：基础网络 + VPN/组网 + 科学上网 + 监控/广告过滤（不含 NAS/下载/文件管理） |
| `Plus+Docker` | Plus 基础上增加 Docker 支持 |

## 🚀 使用方式

### 自动编译

每周六 00:00（北京时间）自动触发：
1. 检测 `v24.10` / `v25.12` 两个分支是否有新提交（对比 `.github/last_commit/*.txt`）
2. **仅编译有更新的分支**（有更新的分支 × Plus / Plus+Docker）
3. 无任何更新则直接终止任务，不启动编译
4. 编译成功后把最新 commit hash 回写进 `.github/last_commit/`

### 手动编译

在 GitHub Actions 页面手动触发 `Schedule Build`：
- 选择分支（v24.10 / v25.12）
- 选择配置（Plus / Plus+Docker）
- 可选设置 LAN IP
- **无更新时继续编译**（`force_build`，默认不勾选）
  - 不勾选：同样先检测更新，无更新则不编译（日志会提示）
  - 勾选：忽略更新检测，**不论是否有更新都强制编译**所选一组

## 📁 仓库结构

```
├── .github/
│   ├── workflows/
│   │   ├── schedule-build.yml       # 调度 workflow（检测更新 + 触发编译 + 回写标记）
│   │   ├── build-openwrt.yml        # 可复用编译 workflow（workflow_call）
│   │   ├── Delete-Old-Workflows.yml # 清理旧 workflow 运行记录
│   │   └── Delete-Old-Release.yml   # 清理旧 Release / 孤立 Tag（保留固件 Release）
│   └── last_commit/
│       ├── v24.10.txt               # v24.10 分支已编译的源码 hash
│       └── v25.12.txt               # v25.12 分支已编译的源码 hash
├── configs/
│   ├── x86_64_Plus.config
│   └── x86_64_Plus+Docker.config
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