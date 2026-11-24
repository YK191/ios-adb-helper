# ADB 助手 for iOS

一个通过 Wi-Fi 连接 Android 设备无线 ADB（TCP 5555）的 iOS 应用。SwiftUI + 原生 ADB 协议实现。

## 界面预览

> 以下图片按应用实际布局与配色整理，用于展示界面结构。

| 设备 | Shell 终端 | 应用管理 |
| --- | --- | --- |
| ![设备页](docs/screenshots/01-device.png) | ![终端页](docs/screenshots/02-terminal.png) | ![应用页](docs/screenshots/03-apps.png) |

| 文件管理 | 设置 |
| --- | --- |
| ![文件页](docs/screenshots/04-files.png) | ![设置页](docs/screenshots/05-settings.png) |

预览图由 `scripts/gen_screenshots.py` 生成，修改界面样式后可用该脚本重新生成。

## 功能

| 功能 | 说明 |
| --- | --- |
| 无线连接 | 输入 IP:端口（默认 5555），RSA 密钥认证，连接记录 |
| 设备信息 | 22 项只读属性：型号、品牌、硬件平台、内核、SELinux、活动槽、启动验证、存储、安全补丁等 |
| 快捷控制 | 电源/Home/返回/最近任务/音量、亮度、DPI、分辨率、旋转、重启模式 |
| Shell 终端 | 任意 `adb shell` 命令、快捷命令、命令历史、复制输出 |
| 应用管理 | 用户/系统应用列表、搜索、启动、强停、冻结/解冻、清数据、卸载、安装 APK |
| 文件管理 | 浏览设备目录、上传本地文件、下载文件到「文件」App、删除文件 |
| 截图 / 录像 | 截图预览并保存到相册；录像只有「截图 / 录像」两个小按钮，点录像后随时可停止，MP4 自动拉取到「文件」App |
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

## 二、重要说明

- 本工程内置一把 ADB RSA 私钥（`ADBHelper/AdbKeyData.swift`）。任何拿到这把密钥的人，只要你的 Android 设备曾授权过它，就能通过 Wi-Fi 连接你的设备。若介意，可运行 `python3 scripts/gen_adb_key.py` 重新生成密钥并重新编译，之后需要在每台 Android 设备上重新授权。
- 截图通过 `exec-out screencap -p` 直接把 PNG 数据流传回 iPhone，**不会在被控设备写入任何文件**。
- 录像使用 Android 自带的 `screenrecord`，以后台进程启动并保存 PID，点「停止录像」即发送 `SIGINT` 正常结束并拉取文件；不再设置录像时长，手动停止即可（系统自身最长约 180 秒）。录像**不含声音**，部分机型/模拟器可能不支持。`screenrecord` 必须先把 MP4 写到设备临时目录，本应用使用 `/data/local/tmp/adbhelper-*.mp4`（不进入相册/媒体库），拉取后立即删除；即使拉取失败也会尽力清理，下次连接时还会自动清理此前的残留文件。
- 本应用应在合法设备、获得机主明确授权的前提下使用。
- 本机没有 macOS/Swift 编译器，未经本地编译；云端 GitHub Actions（macOS）已完成一次成功编译，编译错误已修复。若以后改代码后 Actions 报错，把日志贴回来即可继续修。

## 目录结构

```
ios-adb-helper/
├── ADBHelper/
│   ├── ADBHelperApp.swift       应用入口
│   ├── AdbProtocol.swift        ADB 包协议、TCP 传输、RSA 认证
│   ├── AdbDevice.swift          设备操作与文件同步
│   ├── AdbKeyData.swift         生成的 RSA 密钥（勿手改）
│   ├── Theme.swift              统一视觉风格与复用组件
│   ├── Assets.xcassets          应用图标
│   ├── DeviceViewModel.swift    共享状态
│   ├── Models.swift             数据模型
│   ├── Info.plist
│   └── Views/                   各个功能页面
├── scripts/gen_adb_key.py       密钥生成脚本
├── scripts/gen_icon.py          App 图标生成脚本
├── scripts/gen_screenshots.py   界面预览图生成脚本
├── docs/screenshots/            README 界面预览图
├── project.yml                  XcodeGen 工程描述
└── .github/workflows/build.yml   云编译配置
```
