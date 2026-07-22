# 暮光计时

一个现代 macOS SwiftUI 倒计时器，采用浅色暮光风格，支持多窗口、常用计时、自定义提示音、内置提示音、试听、音量、循环计时、系统通知和快捷键。

## 功能

- 精确到秒的自定义倒计时
- 每个窗口独立的倒计时、标题和提醒声音
- 内置提示音下拉选择，也可以选择本地音频
- 常用计时的添加、载入和删除
- 自动开始下一轮和系统通知开关
- 倒计时完成状态与声音播放提示
- 空格开始/暂停，`⌘R` 重置

## 系统要求

- macOS 13.0 或更高版本
- 当前构建脚本生成 Apple Silicon (`arm64`) 版本
- Intel Mac 需要后续 Universal (`arm64 + x86_64`) 构建

## 下载与安装

1. 打开项目的 [GitHub Releases](https://github.com/Estellalee/twilight-timer/releases/latest) 页面。
2. 在 Assets 中下载 `twilight-timer-v1.5.0.zip`。
3. 双击 ZIP 解压，将 `暮光计时.app` 拖入 macOS 的“应用程序”文件夹。
4. 第一次启动时，右键点击 `暮光计时.app`，选择“打开”，然后在系统提示中再次选择“打开”。
5. 如果出现“无法验证开发者”或“Apple 无法检查其是否包含恶意软件”：确认安装包来自本项目的 Releases 页面，然后点击“取消”，再回到“应用程序”文件夹右键点击 App，选择“打开”。
6. 如果仍然无法启动，请打开“系统设置 → 隐私与安全性”，向下找到“已阻止暮光计时”的提示，点击“仍要打开”，再重新启动 App。
7. 如果提示“App 已损坏”或“无法打开”，不要使用命令绕过安全检查；请先删除当前压缩包和 App，从官方 Release 重新下载并解压。
8. App 首次申请通知权限时选择“允许”，以便在倒计时结束时显示系统通知。

可选：下载后可以在终端验证文件完整性：

```bash
shasum -a 256 twilight-timer-v1.5.0.zip
```

当前 `v1.5.0` 的 SHA-256 是：

```text
71ecc5c44cc2a6efee8afe6dd910da06bd13d95090e1a6fec8ad56e9ff3d6e0a
```

当前 Release 是 Apple Silicon 测试版本，使用临时签名且尚未经过 Apple 公证。请只从本项目的 GitHub Releases 页面下载安装。

## 运行

在 macOS 上进入本目录执行：

```bash
swift run
```

也可以在 Xcode 中打开 `Package.swift` 运行。

## 生成 App

更新 Xcode 或 Command Line Tools 后，在本目录执行：

```bash
chmod +x build-app.sh
./build-app.sh
open "暮光计时.app"
```

## 音频授权

内置音频来自项目中的 `内置铃声确认` 目录。`01_Warm-groovy-109-bpm-funk-loop.wav` 附带 CC BY 4.0 授权说明，发布或再分发时请保留对应鸣谢信息：

Orange Free Sounds, licensed under CC BY 4.0: <https://creativecommons.org/licenses/by/4.0/>

其余音频也应在公开发布前确认拥有可再分发和商业使用的授权。

## 发布说明

源码仓库不包含 `.build`、应用包和压缩包。可安装版本通过 GitHub Releases 提供。
