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
                Text("接下来会打开 iPhone 的「文件」App，请找到并点选一个 .apk 文件（需先把 APK 存到「文件」里，例如通过微信/网盘保存到文件）。选中后会自动推送到设备安装。")
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
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
                case .failure(let error):
                    model.notify(error.localizedDescription)
                }
            }
        }
    }

    private func appRow(_ app: AppInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.accentGradient.opacity(0.85))
                Text(String(app.packageName.split(separator: ".").last?.prefix(1) ?? "A").uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
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
