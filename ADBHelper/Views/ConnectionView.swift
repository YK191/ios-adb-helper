import SwiftUI
import Foundation
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
        .tint(AppTheme.mint)
        .overlay(alignment: .bottom) {
            if !model.toast.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppTheme.mint)
                    Text(model.toast)
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 78)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.toast)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var screenshot: UIImage?
    @State private var showScreenshot = false
    @State private var showHelp = false
    @State private var recording: ScreenRecording?
    @State private var elapsed = 0
    @State private var isStopping = false
    @State private var isCapturing = false

    private struct InfoKey: Identifiable {
        let title: String
        let key: String
        let icon: String
        var id: String { key }
    }

    private let infoKeys: [InfoKey] = [
        InfoKey(title: "型号", key: "ro.product.model", icon: "iphone"),
        InfoKey(title: "品牌", key: "ro.product.brand", icon: "building.2"),
        InfoKey(title: "设备名", key: "ro.product.device", icon: "deviceshape"),
        InfoKey(title: "安卓版本", key: "ro.build.version.release", icon: "square.stack.3d.up"),
        InfoKey(title: "SDK", key: "ro.build.version.sdk", icon: "chevron.left.forwardslash.chevron.right"),
        InfoKey(title: "序列号", key: "ro.serialno", icon: "number"),
        InfoKey(title: "制造商", key: "ro.product.manufacturer", icon: "building.2.fill"),
        InfoKey(title: "产品代号", key: "ro.product.name", icon: "app.badge"),
        InfoKey(title: "硬件平台", key: "ro.board.platform", icon: "cpu"),
        InfoKey(title: "CPU 架构", key: "ro.product.cpu.abilist", icon: "cpu.fill"),
        InfoKey(title: "编译 ID", key: "ro.build.id", icon: "number.circle"),
        InfoKey(title: "编译日期", key: "ro.build.date", icon: "calendar"),
        InfoKey(title: "增量版本", key: "ro.build.version.incremental", icon: "number.circle.fill"),
        InfoKey(title: "安全补丁", key: "ro.build.version.security_patch", icon: "shield.fill"),
        InfoKey(title: "系统代号", key: "ro.build.version.codename", icon: "square.stack.3d.up.fill"),
        InfoKey(title: "当前活动槽", key: "ro.boot.slot_suffix", icon: "rectangle.3.group"),
        InfoKey(title: "A/B 分区", key: "ro.build.ab_update", icon: "square.on.square"),
        InfoKey(title: "启动验证", key: "adbhelper.bootstate", icon: "checkmark.shield.fill"),
        InfoKey(title: "屏幕密度", key: "ro.sf.lcd_density", icon: "viewfinder"),
        InfoKey(title: "内核版本", key: "adbhelper.kernel", icon: "gearshape.2"),
        InfoKey(title: "SELinux", key: "adbhelper.selinux", icon: "lock.fill"),
        InfoKey(title: "存储用量", key: "adbhelper.storage", icon: "internaldrive"),
    ]

    private let quickControls: [(String, String, String)] = [
        ("Home", "house.fill", "input keyevent 3"),
        ("返回", "arrow.left", "input keyevent 4"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard

                    if model.isConnected {
                        infoCard
                        controlsCard
                    }

                    if !model.history.isEmpty {
                        historyCard
                    }
                }
                .padding(16)
            }
            .appCanvas()
            .navigationTitle("ADB 助手")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
            .sheet(isPresented: $showHelp) { ConnectionHelpView() }
            .sheet(isPresented: $showScreenshot) {
                NavigationStack {
                    ZStack {
                        AppTheme.ink.ignoresSafeArea()
                        if let image = screenshot {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else if isCapturing {
                            VStack(spacing: 12) {
                                ProgressView().tint(AppTheme.mint)
                                Text("正在截取屏幕…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("截图数据无法预览")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("设备截图")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("关闭") { showScreenshot = false }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("保存") { saveScreenshot() }
                                .disabled(screenshot == nil)
                        }
                    }
                }
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.accentGradient)
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text("无线 ADB 连接")
                        .font(.headline)
                    Text("IP + 端口，需在同一局域网")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                StatusPill(connected: model.isConnected, text: model.isConnected ? "已连接" : "未连接")
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(AppTheme.mint)
                    TextField("设备 IP，例如 192.168.1.20", text: $model.host)
                        .textContentType(.none)
                        .keyboardType(.decimalPad)
                        .autocapitalization(.none)
                        .font(.subheadline.monospacedDigit())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                HStack(spacing: 10) {
                    Image(systemName: "number")
                        .foregroundStyle(AppTheme.blue)
                    TextField("端口", text: $model.port)
                        .keyboardType(.numberPad)
                        .font(.subheadline.monospacedDigit())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    model.connect()
                } label: {
                    Label(
                        model.isConnecting ? "连接中…" : (model.isConnected ? "已连接" : "连接设备"),
                        systemImage: "wifi"
                    )
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(model.isConnected)

                Button {
                    model.disconnect()
                } label: {
                    Label("断开", systemImage: "circle.slash")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(!model.isConnected)
            }

            if !model.banner.isEmpty {
                Text(model.banner)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .appCard(padding: 16)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "设备信息", systemImage: "iphone", subtitle: model.status)
                Button {
                    model.refreshInfo()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(SoftButtonStyle())
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) {
                ForEach(infoKeys) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: item.icon).font(.caption2)
                            Text(item.title).font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        Text(model.deviceInfo[item.key] ?? "—")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .appCard()
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "快捷控制", systemImage: "bolt.fill", subtitle: "Home · 返回 · 截图 · 录像")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(quickControls, id: \.0) { item in
                    Button {
                        model.run(item.2, success: "\(item.0) 已执行")
                    } label: {
                        controlTile(icon: item.1, label: item.0)
                    }
                    .buttonStyle(.plain)
                }

                Button { takeScreenshot() } label: {
                    controlTile(icon: "camera.fill", label: "截图")
                }
                .buttonStyle(.plain)

                if let activeRecording = recording {
                    Button { stopRecording(activeRecording) } label: {
                        controlTile(
                            icon: "square.fill",
                            label: isStopping ? "保存中" : timeString(elapsed),
                            tint: AppTheme.danger
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isStopping)
                } else {
                    Button { startRecording() } label: {
                        controlTile(icon: "video.fill", label: "录像")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .appCard()
    }

    private func controlTile(icon: String, label: String, tint: Color = AppTheme.mint) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(tint == AppTheme.mint ? .primary : tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "连接记录", systemImage: "clock.arrow.circlepath", subtitle: "点击直接连接")
            FlowLayout(spacing: 8) {
                ForEach(model.history) { record in
                    Button {
                        model.connect(host: record.host, port: UInt16(record.port) ?? 5555)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wifi")
                            Text("\(record.host):\(record.port)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(AppTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .appCard()
    }

    private func startRecording() {
        guard model.ensureConnected() else { return }
        isStopping = false
        model.device.startScreenRecording { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let session):
                    recording = session
                    elapsed = 0
                    model.notify("已开始录像，可随时点击停止")
                    tickRecording()
                case .failure(let error):
                    model.notify("录制失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func stopRecording(_ session: ScreenRecording) {
        guard !isStopping else { return }
        isStopping = true
        model.device.stopScreenRecording(session) { [self] result in
            DispatchQueue.main.async {
                isStopping = false
                recording = nil
                elapsed = 0
                switch result {
                case .success(let url):
                    saveVideoToPhotos(url)
                case .failure(let error):
                    model.notify("保存失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 录像默认保存到系统相册；权限被拒或保存失败时把文件留在「文件」App 里，不丢数据。
    private func saveVideoToPhotos(_ url: URL) {
        let handleAuthorization: (@escaping (Bool) -> Void) -> Void = { done in
            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    done(status == .authorized || status == .limited)
                }
            } else {
                PHPhotoLibrary.requestAuthorization { status in
                    done(status == .authorized || status == .limited)
                }
            }
        }

        handleAuthorization { allowed in
            guard allowed else {
                DispatchQueue.main.async {
                    model.notify("未获得相册权限，录像已保存在「文件」App")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        // 相册里已有副本，删掉 App 内的临时文件，避免重复占用空间。
                        try? FileManager.default.removeItem(at: url)
                        model.notify("录像已保存到相册")
                    } else {
                        model.notify("保存到相册失败：\(error?.localizedDescription ?? "未知错误")，录像已保留在「文件」App")
                    }
                }
            }
        }
    }

    private func tickRecording() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            guard recording != nil else { return }
            elapsed += 1
            tickRecording()
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func takeScreenshot() {
        guard model.ensureConnected() else { return }
        screenshot = nil
        isCapturing = true
        showScreenshot = true
        model.device.screenshot { result in
            DispatchQueue.main.async {
                isCapturing = false
                switch result {
                case .success(let data):
                    guard let image = UIImage(data: data) else {
                        showScreenshot = false
                        model.notify("截图数据无法解析（\(data.count) 字节）")
                        return
                    }
                    screenshot = image
                case .failure(let error):
                    showScreenshot = false
                    model.notify("截图失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func saveScreenshot() {
        guard let image = screenshot else {
            model.notify("截图尚未就绪")
            return
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                self.writeImageToPhotos(image, allowed: status == .authorized || status == .limited)
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                self.writeImageToPhotos(image, allowed: status == .authorized || status == .limited)
            }
        }
    }

    private func writeImageToPhotos(_ image: UIImage, allowed: Bool) {
        guard allowed else {
            DispatchQueue.main.async { model.notify("需要相册权限才能保存截图") }
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            DispatchQueue.main.async {
                showScreenshot = false
                model.notify(success ? "截图已保存到相册" : "保存失败：\(error?.localizedDescription ?? "未知错误")")
            }
        }
    }
}

// Simple wrapping layout used for connection history chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ConnectionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String, String)] = [
        ("1", "开启开发者选项", "Android 设备进入「设置 → 开发者选项」，打开「USB 调试」。", "gearshape"),
        ("2", "打开无线 ADB", "部分 ROM 有「无线 ADB」开关（端口通常 5555），或先用电脑执行一次 adb tcpip 5555。", "wifi"),
        ("3", "同一局域网", "iPhone 与 Android 连接同一个 Wi-Fi，路由器不能开启访客网络或 AP 隔离。", "network"),
        ("4", "确认授权", "首次连接时手机上会弹出 RSA 指纹确认，勾选「一律允许」后确定。", "hand.raised"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppTheme.accentGradient)
                        Text("连接前准备")
                            .font(.title3.weight(.bold))
                        Text("本应用通过 Wi-Fi 直连 Android 的 ADB 守护进程（TCP 5555），不需要电脑，也不需要越狱。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .appCard(padding: 16)

                    ForEach(steps, id: \.0) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Text(step.0)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(AppTheme.accentGradient, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.1).font(.subheadline.weight(.semibold))
                                Text(step.2).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: step.3).foregroundStyle(AppTheme.mint.opacity(0.8))
                        }
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("平台限制", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("未越狱 iOS 无法访问 USB 硬件，因此不支持 USB ADB、Fastboot 刷机、scrcpy 实时投屏和 Android 11+ 无线调试配对码配对。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .appCard()
                }
                .padding(16)
            }
            .appCanvas()
            .navigationTitle("连接说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }
}
