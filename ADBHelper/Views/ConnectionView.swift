import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @EnvironmentObject var model: DeviceViewModel

    var body: some View {
        TabView {
            ConnectionView()
                .tabItem { Label("设备", systemImage: "link.circle.fill") }
            ShellView()
                .tabItem { Label("终端", systemImage: "terminal.fill") }
            AppsView()
                .tabItem { Label("应用", systemImage: "square.grid.2x2.fill") }
            FilesView()
                .tabItem { Label("文件", systemImage: "folder.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .bottom) {
            if !model.toast.isEmpty {
                Text(model.toast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 72)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: model.toast)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var screenshot: UIImage?
    @State private var showScreenshot = false
    @State private var showHelp = false
    @State private var brightness = "128"
    @State private var density = "480"
    @State private var resolution = ""

    private struct InfoKey: Identifiable {
        let title: String
        let key: String
        var id: String { key }
    }

    private let infoKeys: [InfoKey] = [
        InfoKey(title: "设备型号", key: "ro.product.model"),
        InfoKey(title: "品牌", key: "ro.product.brand"),
        InfoKey(title: "设备名称", key: "ro.product.device"),
        InfoKey(title: "系统版本", key: "ro.build.version.release"),
        InfoKey(title: "SDK", key: "ro.build.version.sdk"),
        InfoKey(title: "序列号", key: "ro.serialno"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    TextField("设备 IP，例如 192.168.1.20", text: $model.host)
                        .textContentType(.none)
                        .keyboardType(.decimalPad)
                        .autocapitalization(.none)
                    TextField("端口", text: $model.port)
                        .keyboardType(.numberPad)
                    HStack {
                        Button(action: model.connect) {
                            Label("连接", systemImage: "wifi")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isConnected)
                        Button("断开") { model.disconnect() }
                            .disabled(!model.isConnected)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: model.isConnected ? "checkmark.circle.fill" : "circle")
                        Text(model.status)
                    }
                    .foregroundStyle(model.isConnected ? .green : .secondary)
                    .font(.footnote)
                    if !model.banner.isEmpty {
                        Text(model.banner).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("开启无线 ADB 的说明") { showHelp = true }
                        .font(.footnote)
                }

                if model.isConnected {
                    Section("设备信息") {
                        Button("刷新") { model.refreshInfo() }
                        ForEach(infoKeys) { item in
                            HStack {
                                Text(item.title).foregroundStyle(.secondary)
                                Spacer()
                                Text(model.deviceInfo[item.key] ?? "—").textSelection(.enabled)
                            }
                            .font(.footnote)
                        }
                    }

                    Section("快捷控制") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                            controlButton("电源", "power") { model.run("input keyevent 26") }
                            controlButton("Home", "house") { model.run("input keyevent 3") }
                            controlButton("返回", "arrow.left") { model.run("input keyevent 4") }
                            controlButton("最近任务", "square.on.square") { model.run("input keyevent 187") }
                            controlButton("截图", "camera") { takeScreenshot() }
                            controlButton("音量+", "speaker.wave.2") { model.run("input keyevent 24") }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("屏幕与显示") {
                        HStack {
                            TextField("亮度 0-255", text: $brightness).keyboardType(.numberPad)
                            Button("设置") { model.run("settings put system screen_brightness \(brightness)") }
                        }
                        HStack {
                            TextField("DPI", text: $density).keyboardType(.numberPad)
                            Button("设置") { model.run("wm density \(density)") }
                        }
                        HStack {
                            TextField("分辨率，例如 1080x2400", text: $resolution).autocapitalization(.none)
                            Button("设置") {
                                guard !resolution.isEmpty else { model.notify("请输入分辨率"); return }
                                model.run("wm size \(resolution)")
                            }
                        }
                        HStack {
                            Button("恢复 DPI") { model.run("wm density reset") }
                            Button("恢复分辨率") { model.run("wm size reset") }
                        }
                        HStack {
                            Button("自动旋转") { model.run("settings put system accelerometer_rotation 1") }
                            Button("固定竖屏") {
                                model.run("settings put system accelerometer_rotation 0; settings put system user_rotation 0")
                            }
                        }
                    }

                    Section("重启") {
                        HStack {
                            Button("系统") { model.run("reboot", success: "已发送重启命令") }
                            Button("Recovery") { model.run("reboot recovery", success: "已发送重启命令") }
                            Button("Bootloader") { model.run("reboot bootloader", success: "已发送重启命令") }
                        }
                    }
                }

                if !model.history.isEmpty {
                    Section("连接记录") {
                        ForEach(model.history) { record in
                            Button("\(record.host):\(record.port)") {
                                model.host = record.host
                                model.port = String(record.port)
                            }
                        }
                    }
                }
            }
            .navigationTitle("ADB 助手")
            .sheet(isPresented: $showHelp) { ConnectionHelpView() }
            .sheet(isPresented: $showScreenshot) {
                NavigationStack {
                    Image(uiImage: screenshot ?? UIImage())
                        .resizable()
                        .scaledToFit()
                        .navigationTitle("截图")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("保存") { saveScreenshot() }
                            }
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("关闭") { showScreenshot = false }
                            }
                        }
                }
            }
        }
    }

    private func controlButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func takeScreenshot() {
        guard model.ensureConnected() else { return }
        model.device.screenshot { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    screenshot = UIImage(data: data)
                    showScreenshot = screenshot != nil
                    if screenshot == nil { model.notify("截图数据无法解析") }
                case .failure(let error):
                    model.notify(error.localizedDescription)
                }
            }
        }
    }

    private func saveScreenshot() {
        guard let image = screenshot else { return }
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { model.notify("需要相册权限才能保存截图") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                DispatchQueue.main.async {
                    model.notify(success ? "截图已保存到相册" : "保存失败：\(error?.localizedDescription ?? "未知错误")")
                }
            }
        }
    }
}

struct ConnectionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        Text("工作原理").font(.headline)
                        Text("本应用通过 Wi-Fi 直连 Android 设备的 ADB 守护进程（TCP 5555），不依赖电脑。手机和 iPhone 必须在同一局域网，且不能开启访客网络隔离或客户端隔离。")
                    }
                    Group {
                        Text("在 Android 上开启").font(.headline)
                        Text("开发者选项 → 开启「USB 调试」。部分系统（如 MIUI、ColorOS）有「无线 ADB」开关，打开后端口通常是 5555。Android 11+ 的「无线调试」使用动态端口和配对码，本应用暂不支持该配对方式。")
                        Text("如果设备只开启了 USB 调试，可先用电脑执行一次 adb tcpip 5555 让设备监听 5555 端口。")
                    }
                    Group {
                        Text("首次连接授权").font(.headline)
                        Text("连接时手机会弹出「允许 USB 调试吗？」的 RSA 指纹确认，请勾选「一律允许」后确定。之后即可免确认连接。")
                    }
                    Group {
                        Text("不支持的功能").font(.headline)
                        Text("iOS 未越狱时无法直接访问 USB 设备，因此 USB ADB、Fastboot 刷机、scrcpy 实时投屏、无线调试配对码配对均无法实现。")
                    }
                }
                .font(.body)
                .padding()
            }
            .navigationTitle("连接说明")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }
}
