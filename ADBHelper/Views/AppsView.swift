import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var apps: [AppInfo] = []
    @State private var filter = ""
    @State private var showSystem = false
    @State private var selected: AppInfo?
    @State private var showImporter = false
    @State private var showInstallTip = false
    @State private var isLoading = false

    private var filtered: [AppInfo] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.packageName.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("类型", selection: $showSystem) {
                    Text("用户应用").tag(false)
                    Text("系统应用").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .onChange(of: showSystem) { _ in load() }

                ZStack {
                    AppTheme.canvas.ignoresSafeArea()
                    if filtered.isEmpty {
                        EmptyStateView(
                            systemImage: isLoading ? "hourglass" : "square.stack.3d.down.right",
                            title: isLoading ? "正在读取应用…" : (filter.isEmpty ? "暂无应用列表" : "没有匹配的应用"),
                            message: isLoading ? "正在通过 ADB 获取已安装包" : "点击右上角刷新按钮重新读取"
                        )
                    } else {
                        List(filtered) { app in
                            Button { selected = app } label: {
                                appRow(app)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.card)
                            .listRowSeparatorTint(AppTheme.border)
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("应用管理")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $filter, prompt: "搜索包名")
            .tint(AppTheme.mint)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        load()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showInstallTip = true
                    } label: {
                        Label("安装", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .task { load() }
            .confirmationDialog(
                Text(selected?.packageName ?? ""),
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                )
            ) {
                Button("启动", systemImage: "play.fill") { act("launch") }
                Button("强行停止", systemImage: "stop.fill") { act("stop") }
                Button("冻结 / 停用", systemImage: "snowflake") { act("freeze") }
                Button("解冻 / 启用", systemImage: "sun.max") { act("unfreeze") }
                Button("清除数据", systemImage: "trash") { act("clear") }
                Button("卸载", systemImage: "square.and.arrow.up", role: .destructive) { act("uninstall") }
                Button("取消", role: .cancel) {}
            }
            .alert("安装 APK", isPresented: $showInstallTip) {
                Button("取消", role: .cancel) {}
                Button("选择文件") { showImporter = true }
            } message: {
                Text("会打开系统文件选择器，点一下 .apk 文件就会自动选中返回，然后开始安装（不需要先连接设备）。如果列表里没有文件，请先在「文件」App 里把 APK 存到「我的 iPhone」中。")
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker { url in
                    showImporter = false
                    model.notify("已选择 \(url.lastPathComponent)")
                    let didAccess = url.startAccessingSecurityScopedResource()
                    model.device.installApk(from: url) { installResult in
                        if didAccess { url.stopAccessingSecurityScopedResource() }
                        DispatchQueue.main.async {
                            switch installResult {
                            case .success:
                                model.notify("安装完成")
                                load()
                            case .failure(let error):
                                model.notify(error.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
    }

    private static let iconPalettes: [(UInt32, UInt32)] = [
        (0x4F8DF7, 0x36C9C0), (0xF2994A, 0xF2C94C), (0x9B6BEA, 0xE76DD0),
        (0x2FBF71, 0x8BD450), (0xE5534B, 0xF28B5D), (0x3AA7F2, 0x5B6EE8),
        (0x00A8A8, 0x3FD0C9), (0xB6794E, 0xE0A76B), (0x706FD3, 0x9799EE),
        (0xEB5757, 0xF7696B), (0x27A0A6, 0x6FD3C7), (0xC2569D, 0xF08BBE),
    ]

    /// Stable hash (djb2) so the same package always gets the same colors.
    private func appColors(for package: String) -> (Color, Color) {
        var hash: UInt64 = 5381
        for byte in package.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let pair = Self.iconPalettes[Int(hash % UInt64(Self.iconPalettes.count))]
        return (Color(pair.0), Color(pair.1))
    }

    private func appInitial(for package: String) -> String {
        let segments = package.split(separator: ".")
        let last = segments.last.map(String.init) ?? package
        let character = last.first ?? package.first ?? "A"
        return String(character).uppercased()
    }

    private func appRow(_ app: AppInfo) -> some View {
        let colors = appColors(for: app.packageName)
        let initial = appInitial(for: app.packageName)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(
                        colors: [colors.0, colors.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text(initial)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.packageName)
                    .font(.footlineWeight())
                    .textSelection(.enabled)
                    .lineLimit(1)
                Text(showSystem ? "系统应用" : "用户应用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func load() {
        guard model.ensureConnected() else { return }
        isLoading = true
        model.device.listPackages(system: showSystem) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let list): apps = list
                case .failure(let error): model.notify(error.localizedDescription)
                }
            }
        }
    }

    private func act(_ action: String) {
        guard let app = selected else { return }
        selected = nil
        let messages = [
            "launch": "已发送启动命令", "stop": "已强行停止", "uninstall": "已卸载",
            "freeze": "已冻结", "unfreeze": "已解冻", "clear": "已清除数据",
        ]
        model.device.appAction(action, package: app.packageName) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    model.notify(messages[action] ?? "操作完成")
                    if action == "uninstall" { load() }
                case .failure(let error):
                    model.notify(error.localizedDescription)
                }
            }
        }
    }
}

private extension Font {
    static func footlineWeight() -> Font {
        .footnote.weight(.medium)
    }
}
