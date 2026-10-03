# Meme Radar Android

[English](README.md) | [简体中文](README_zh-CN.md)

非官方社区维护的 Meme Radar Android 移植版。

## Features

- 独立的 Android 扫描客户端
- 用户自定义提供 AVE API Key
- 支持 Solana, BSC, Base, Ethereum, Robinhood 链
- Live Candidates / 实时候选
- Discovery Score / 发现评分
- PRIORITY 区间
- Candidate 排序
- 后台扫描
- 通过 Android 前台服务实现息屏扫描
- 新的 Candidate 通知
- 本地通知去重

*注意: Radar Candidate ≠ 买入建议。*

## Installation

1. 从 GitHub Releases 下载 APK
2. 安装 APK
3. 打开 Settings (设置)
4. 输入你自己的 AVE API Key
5. 测试连接
6. 选择链
7. 启动 Radar

*App 不包含共享的 AVE API Key。每位用户必须提供自己的 Key。*

**API Key Storage:**
- 使用 Android secure storage 本地保存
- 不会有意上传至开发者服务器
- 不包含在 GitHub 源码或 release APK 中

## Background Behavior

点击 "Start Radar" 后:
- 立即执行第一次扫描
- 随后的扫描每 5 分钟执行一次
- Android 前台服务保持 Radar 在后台活跃
- Radar 运行时预期会显示持续的 Android 系统通知
- 新的合格 Live Candidates / 实时候选可能会触发单独的 Candidate 通知

*电池优化说明:* 不同的 Android OEM 电池优化可能会影响长期的后台行为。
*Android 15+ 说明:* 本应用使用 dataSync 前台服务。如果应用/系统组合受到 Android 系统对 dataSync 前台服务运行时长的限制，长期的连续后台扫描可能会受限。

## Privacy / Data Handling

- 扫描请求直接从 Android 设备发出
- AVE API Key 由用户自己提供
- 不需要开发者 VPS 即可进行 Radar 扫描
- 不需要钱包私钥
- 不执行交易
- 不执行 swap
- 不执行自动下单

网络请求会访问本项目使用的以下第三方 API：
- AVE
- DexScreener
- GoPlus

*这些第三方服务受其各自的服务条款和隐私政策约束。*

## Beta Disclaimer

**Beta 测试版软件。**
这是非官方的社区 Beta 版本。它可能包含错误，并且不应被视为财务建议。Meme Radar 仅将市场候选标的浮现以供审查；它不保证代币安全、盈利或未来表现。

## License

基于原项目 Meme Radar: https://github.com/nhovongoc0-max/meme-radar
原项目/作者鸣谢: nhovongoc0-max
此 Android 移植版为非官方/社区维护。
源码遵循 AGPL-3.0-only 协议分发。
本项目不是原作者官方 Android 版本。
