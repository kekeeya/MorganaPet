# Mona — 桌面上的摩尔加纳

[![Platform](https://img.shields.io/badge/platform-macOS-black)](https://github.com/kekeeya/MorganaPet/releases)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue)](https://github.com/kekeeya/MorganaPet/releases)
[![Release](https://img.shields.io/github/v/release/kekeeya/MorganaPet?include_prereleases)](https://github.com/kekeeya/MorganaPet/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Fan Project](https://img.shields.io/badge/fan%20project-non--commercial-ff69b4)](#-版权说明)

**基于女神异闻录5摩尔加纳形象的Mac桌面宠物。目前可以监控 Claude 和 Codex 的额度，以及电脑运行的基本情况。**

纯 macOS 原生应用，SwiftUI + AppKit，无网络请求，无遥测，无后台服务。

<p align="center">
  <img src="docs/Desktop.gif" width="564" alt="摩尔加纳在桌面上走动">
</p>


## 📑 目录

- [✨ 功能一览](#-功能一览)
- [🚀 安装](#-安装)
  - [系统要求](#系统要求)
  - [安装流程](#安装流程)
  - [⚠️ 第一次打开被拦下](#-第一次打开被拦下)
  - [确认启动成功](#确认启动成功)
- [📊 额度监控](#-额度监控)
  - [隐私声明](#隐私声明)
  - [Codex 用量](#codex-用量)
  - [Claude 订阅额度](#claude-订阅额度)
- [🖥️ 本机状态](#-本机状态)
- [🛠️ 关于源码](#-关于源码)
- [📝 License](#-license)
- [⚖️ 版权说明](#-版权说明)


## ✨ 功能一览

| 你的操作 | 他的反应 |
|---|---|
| 🖱️ **点他一下** | 戳一下，有几率随口说句话；连着快戳会从不耐烦升级到生气 |
| ✋ **摸头 / 摸肚子 / 摸脚 / 摸尾巴** | 四个部位反应各不相同，摸尾巴他会炸毛 |
| 🐾 **戳他但他没话说** | 「喵呜」一声 |
| 🕐 **到整点** | 主动报时 |
| 🌙 **深夜还在敲代码** | 随机催你去睡 |
| 😴 **凌晨没人理他** | 00:00–06:00 十分钟无交互就打瞌睡 |
| 🖱️ **右键** | 查看 Codex 用量、Claude 额度、本机状态、打开设置 |



## 🚀 安装

### 系统要求

| 项目 | 要求 |
|---|---|
| 系统 | **macOS 26.0 或更高** |
| 架构 | Intel 与 Apple Silicon 均可（通用二进制） |
| 依赖 | 无。不用装 Xcode，不用装任何运行时 |

> ⚠️ 目前只在 **Apple Silicon + macOS 26.5** 上实机验证过。Intel 那半边和 26.0–26.4
> 编译产物齐全，但没有真机跑过。遇到问题欢迎开 issue。

### 安装流程

1. 从 **[Releases](https://github.com/kekeeya/MorganaPet/releases)** 下载 `Mona-x.y.z.dmg`
2. 双击挂载，把 **Mona** 拖进 **应用程序**
3. 双击打开 —— **第一次会被拦下，见下一节**

### ⚠️ 第一次打开被拦下

你会看到这个：

> 「Apple 无法验证「Mona」是否包含可能危害 Mac 安全或泄漏隐私的恶意软件。」

**这是正常的。** 本项目没有 Apple 开发者证书（$99/年），所有未签名的 macOS 应用第一次打开都是这个待遇。

**别点「移到废纸篓」**，按下面走：

| 步骤 | 操作 |
|---|---|
| 1️⃣ | 点 **「完成」** 关掉弹窗 |
| 2️⃣ | 打开 **系统设置 → 隐私与安全性** |
| 3️⃣ | 往下滚到「安全性」，会看到「已阻止使用「Mona」…」，点 **「仍要打开」** |
| 4️⃣ | 再次确认，必要时用 Touch ID 或密码验证 |

之后正常双击即可，**只需放行这一次**。

> 🚫 **不要用 `xattr -dr com.apple.quarantine` 那条命令。** 网上到处都是这个做法，但从
> macOS 14 起，修改别的 app 的包内容需要终端先拿到「App 管理」权限，否则只会给你一句
> `Operation not permitted`，绕的圈子比走图形界面还大。

### 确认启动成功

Mona **没有程序坞图标**，所以别盯着程序坞看：

- ✅ **状态栏**出现一个猫头图标
- ✅ **桌面上**出现摩尔加纳

从状态栏图标可以显示、隐藏和退出。


## 📊 额度监控

### 隐私声明

「查看 Codex 用量」和「查看 Claude 额度」读的都是**你电脑上已经存在的本地文件**：

- **不联网，不上传任何东西**
- **完全不碰登录凭据**
- **只读**，不修改、不删除任何文件
- **不读你和 Codex / Claude 的任何对话内容**，只取额度那几个数字

### Codex 用量

**装了 Codex 就能用，零配置。** 默认读 `~/.codex`（Codex 的默认主目录）。如果你用 `CODEX_HOME` 挪过位置，在设置里填新路径即可。

> ⏳ **读到的不是实时数据。**
>
> Codex 只在你用它的时候才把额度写进会话记录，所以 Mona 看到的是**上一次会话留下的快照**。
> 一天没开 Codex，读到的就是一天前的数字。
>
> Codex 没有提供任何官方的实时来源，这个绕不过去。Mona 的做法是**如实说明**：超过 30 分钟的
> 记录，摩尔加纳会先说「这是 xx 前的记录了」再报数字。**和 Codex app 对不上时，以 app 为准。**

<details>
<summary>📐 技术细节：他到底在读什么</summary>

读的是 Codex CLI **未公开的内部 JSONL 格式**（额度写在会话记录的 `event_msg` / `token_count` 事件里），字段随时可能变——不像 Claude 那条走的是有官方文档的 status line。

窗口长度按记录里的 `window_minutes` 判断，**不假设哪个槽位对应哪个窗口**：不同套餐下 `primary` 可能是 5 小时窗口也可能是 7 天窗口，写死会报出错误的标签。

环境变量对从 Dock 启动的应用无效（GUI 应用继承的是 launchd 环境，读不到 `~/.zshrc` 里的变量），所以设置里填的路径优先级高于 `CODEX_HOME`。

</details>

### Claude 订阅额度

> ⚠️ **只对 Claude.ai 的 Pro / Max 订阅有效。** 5 小时和 7 天这两个窗口是订阅套餐特有的概念，
> 用 API key 认证的 Claude Code 没有这两个字段。

需要**一次性配置**，全程在设置窗口里完成：

| 步骤 | 操作 |
|---|---|
| 1️⃣ | 右键摩尔加纳 → **设置…** |
| 2️⃣ | 「Claude 额度读取」下点 **「复制配置」** |
| 3️⃣ | 打开 `~/.claude/settings.json`，把复制的内容粘进去 |
| 4️⃣ | 重开一个 Claude Code 会话，设置窗口里会变成 **「✓ 已找到额度信息，xx 前」** |

复制出来的配置里写的是**你这台机器上的绝对路径**，和设置里填的一致，所以你改过路径也不会对不上。用到的 `tee` 和 `jq` 都是 macOS 自带的，**不用装任何东西**。

配置完还有个附赠效果：Claude Code 底部会多显示一行 `5h 23% · 7d 41%`。

> 数据只在 Claude Code 运行时更新。关掉之后 Mona 读到的是最后一次的值，摩尔加纳会直接说出这是多久以前的。

<details>
<summary>📐 技术细节：为什么要绕这一道</summary>

个人 Pro/Max 账号**没有可查询用量的公开 API**——Admin API 对个人账号不开放，而 API key 根本没有 5 小时／7 天这个概念。Claude Code 自己知道额度，但只放在进程内存里，磁盘上不落文件。

它唯一对外交出这份数据的地方是 **status line**：你指定一条命令，Claude Code 每次会话更新时把当前会话的完整 JSON（含 `rate_limits`）喂给它的 stdin。所以做法是让那条命令顺手存一份到磁盘。**这是有官方文档的机制，不是逆向出来的。**

社区里也有拿 OAuth token 调未公开端点取实时数据的做法，**Mona 不这么做**——那需要碰你的登录凭据。

几点须知：

- `rate_limits` 要等会话产生**第一次 API 响应**之后才出现，新开会话时是空的，属于正常。两个窗口可能各自独立缺失，Mona 只报读到的那个，**不推算另一个**。
- **`statusLine` 全局只有一个。** 如果你在用别的 Claude Code 状态栏工具（比如 `claude-monitor --statusline`），加这条会覆盖掉它。
- 那条命令任何一步失败都静默降级（状态栏显示空行），**不会影响你日常使用 Claude Code**。

</details>


## 🖥️ 本机状态

右键 →「查看本机状态」，摩尔加纳会报 CPU、内存、硬盘、电池和网络：

| 项目 | 报什么 |
|---|---|
| CPU | 系统占用和用户占用分开报 |
| 内存 | 已用 / 空闲，口径对齐活动监视器（应用 + 联动 + 压缩） |
| 硬盘 | 剩余空间 |
| 电池 | 电量、是否在充电；低电量时他会催你插电 |
| 网络 | 当前接口、IP 和实时上下行速率 |

数据全部来自系统 API（`host_statistics` / `IOPSCopyPowerSourcesInfo` / `getifaddrs` 等），5 秒刷新一次。

---

## 🛠️ 关于源码

> ### ⚠️ 这个仓库直接 clone 下来是**构建不过**的
>
> 因为可能的版权问题，仓库里**不含任何美术资源**，`Assets.xcassets` 是空的，构建会在 `actool` 那步失败。
>
> **想用请直接下 [Releases](https://github.com/kekeeya/MorganaPet/releases) 里的 dmg。**

这里放的是代码框架和全部台词配置，供参考和学习。摩尔加纳说的每一句话都在 `Mona/Dialogue/` 下的 JSON 里，按触发场景分成 37 个文件。


## 📝 License

源代码以 **[MIT License](LICENSE)** 发布。

**美术资源不在此许可范围内**——摩尔加纳的形象权利归 Atlus / Sega 所有，本仓库不含也不授权任何美术资源。


## ⚖️ 版权说明

本项目是**非商业粉丝作品**，与 Atlus、Sega 无任何关联，未获其授权或认可。

摩尔加纳及《女神异闻录 5》（Persona 5）相关的一切权利归其各自权利方所有。本项目不收费、不接受捐赠、不含广告。

**若权利方认为本项目有任何不妥，请通过 issue 或邮件联系，我会立即下架相关内容。**

---

<p align="center">
  ⭐ 觉得有意思的话，给个 star 吧 ⭐
</p>
