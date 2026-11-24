import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var apps: [AppInfo] = []
    @State private var filter = ""
    @State private var showSystem = false
    @State private var selected: AppInfo?
    @State private var showImporter = false
    @State private var isLoading = false

    private var filtered: [AppInfo] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.packageName.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Picker("类型", selection: $showSystem) {
                        Text("用户应用").tag(false)
                        Text("系统应用").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button {
                        showSystem.toggle()
                        load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding(.horizontal)

                List(filtered) { app in
                    Button {
                        selected = app
                    } label: {
                        HStack {
                            Image(systemName: "app.badge")
                            Text(app.packageName)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if isLoading { ProgressView() }
                    else if apps.isEmpty {
                        Text("点击刷新按钮读取应用列表").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("应用")
            .toolbar {
                Button("安装 APK") { showImporter = true }
            }
            .task { load() }
            .confirmationDialog(
                Text(selected?.packageName ?? ""),
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                )
            ) {
                Button("启动") { act("launch") }
                Button("强行停止") { act("stop") }
                Button("冻结/停用") { act("freeze") }
                Button("解冻/启用") { act("unfreeze") }
                Button("清除数据") { act("clear") }
                Button("卸载", role: .destructive) { act("uninstall") }
                Button("取消", role: .cancel) {}
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else {
                        model.notify("无法读取所选文件")
                        return
                    }
                    model.device.installApk(from: url) { installResult in
                        url.stopAccessingSecurityScopedResource()
                        DispatchQueue.main.async {
                            switch installResult {
                            case .success:
                                model.notify("安装完成")
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
