# ADB 助手 for iOS

一个通过 Wi-Fi 连接 Android 设备无线 ADB（TCP 5555）的 iOS 应用。SwiftUI + 原生 ADB 协议实现，**不需要越狱**。

## 功能

| 功能 | 说明 |
| --- | --- |
| 无线连接 | 输入 IP:端口（默认 5555），RSA 密钥认证，连接记录 |
| 设备信息 | 型号、品牌、系统版本、SDK、序列号 |
| 快捷控制 | 电源/Home/返回/最近任务/音量、亮度、DPI、分辨率、旋转、重启模式 |
| Shell 终端 | 任意 `adb shell` 命令、快捷命令、命令历史、复制输出 |
| 应用管理 | 用户/系统应用列表、搜索、启动、强停、冻结/解冻、清数据、卸载、安装 APK |
| 文件管理 | 浏览设备目录、上传本地文件、下载文件到「文件」App、删除文件 |
| 截图 | `screencap -p` 截图预览并保存到相册 |
| 日志 | 读取最近 `logcat` 缓冲 |

## 做不到的部分（iOS 系统限制）

未越狱的 iOS **无法直接访问 USB 设备**，因此不能实现：

- USB ADB（你插数据线的方式）
- Fastboot / 刷机 / 分区操作
- scrcpy 实时投屏、相机远控
- Android 11+「无线调试」的配对码（SPAKE2）配对，只能连接已开放 5555 端口的设备
- 通知栏配对后台服务

这是平台能力问题，不是代码可以绕过的。

## 一、在 Android 上准备

1. 打开「开发者选项」→ 开启「USB 调试」。
2. 让设备监听 5555 端口，二选一：
   - 系统自带「无线 ADB」开关（部分国产 ROM 有），打开后默认端口 5555；
   - 或者用电脑执行一次 `adb tcpip 5555`（需要 USB 连接一次，之后可拔线）。
3. iPhone 和 Android 必须在**同一 Wi-Fi / 局域网**，且路由器不能开启 AP 隔离/访客网络隔离。
4. 首次连接时，手机上会弹出「允许 USB 调试吗？」的 RSA 指纹确认，勾选「一律允许」后确定。

## 二、在没有 Mac 的情况下编译 IPA

本项目使用 GitHub Actions 的 macOS 云主机编译，**你只需要一个 GitHub 账号**。

1. 注册/登录 GitHub，新建一个 **Public** 仓库（私有仓库每月也有免费额度，但公开仓库最省心）。
2. 把本目录所有文件上传到仓库根目录（包括隐藏的 `.github/workflows/build.yml`）。
   - 网页上传时忽略 `.github` 文件夹也没关系，可改用 GitHub Desktop 上传完整目录。
3. 打开仓库 → `Actions` → 找到 `Build iOS ADB Helper IPA` → 点击 `Run workflow`（或 push 代码自动触发）。
4. 等待编译完成（一般几分钟），在本次运行的Artifacts里下载 `ADBHelper-unsigned-IPA` ZIP，解压得到 `ADBHelper.ipa`。

这就是**未签名 IPA**，下一步在 Windows 上用免费 Apple ID 签名安装。

> 备选云编译平台：Codemagic、Bitrise（都提供 macOS 构建机），配置思路相同：`xcodegen generate` → `xcodebuild archive` → 打包 Payload 为 ipa。

## 三、在 Windows 上签名并安装

iOS 不认真正意义上的「自签名证书」，所谓自签通常是**用你自己的免费 Apple ID 生成个人开发证书**来侧载。常用工具是 Sideloadly（免费）：

1. 电脑安装 [iTunes](https://www.apple.com/itunes/download/)（Windows 版，提供 Apple 设备驱动）。
2. 下载 [Sideloadly](https://sideloadly.io/) Windows 版并安装。
3. 用数据线把 iPhone 连到电脑，信任此电脑。
4. 打开 Sideloadly：
   - IPA 选择刚下载的 `ADBHelper.ipa`；
   - 输入你的 Apple ID 和密码（建议开启两步验证并使用 App 专用密码）；
   - Device 选择你的 iPhone；
   - 点击 `Start` 开始签名并安装。
5. iPhone 上打开「设置 → 通用 → VPN 与设备管理」→ 点击你的 Apple ID 证书 → 选择「信任」。
6. 回到主屏幕即可打开 App。

**免费 Apple ID 签名的 App 有效期 7 天**，到期后重新用 Sideloadly 签一次即可（数据会保留）。付费开发者账号（¥688/年）可签 1 年。

其他可选签名工具：AltStore、爱思助手「IPA 签名」、Esign。流程类似。

## 四、重要说明

- 本工程内置一把 ADB RSA 私钥（`ADBHelper/AdbKeyData.swift`）。任何拿到这把密钥的人，只要你的 Android 设备曾授权过它，就能通过 Wi-Fi 连接你的设备。若介意，可运行 `python3 scripts/gen_adb_key.py` 重新生成密钥并重新编译，之后需要在每台 Android 设备上重新授权。
- 本应用应在合法设备、获得机主明确授权的前提下使用。
- 我没有 macOS 环境，无法在本地编译验证；工程已按 Xcode 16 / iOS 16 SDK 配置，编译产物由云端 Actions 生成。如果 Actions 报编译错误，把日志贴回来我可以继续修。

## 目录结构

```
ios-adb-helper/
├── ADBHelper/
│   ├── ADBHelperApp.swift       应用入口
│   ├── AdbProtocol.swift        ADB 包协议、TCP 传输、RSA 认证
│   ├── AdbDevice.swift          设备操作与文件同步
│   ├── AdbKeyData.swift         生成的 RSA 密钥（勿手改）
│   ├── DeviceViewModel.swift    共享状态
│   ├── Models.swift             数据模型
│   ├── Info.plist
│   └── Views/                   各个功能页面
├── scripts/gen_adb_key.py       密钥生成脚本
├── project.yml                  XcodeGen 工程描述
└── .github/workflows/build.yml   云编译配置
```
