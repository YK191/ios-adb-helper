import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newCommand = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("关于") {
                    LabeledContent("名称", value: "ADB 助手 for iOS")
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("授权方式", value: "RSA 2048（首次连接需在手机上确认）")
                    LabeledContent("密钥指纹", value: "+6IJs9ePbh2Xs2OpZYVASrfUX2IPyHryESrHqErOzmo=")
                        .font(.caption)
                }

                Section("我的快捷命令") {
                    ForEach(model.quickCommands) { item in
                        VStack(alignment: .leading) {
                            Text(item.name).font(.footnote)
                            Text(item.command).font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.quickCommands.removeAll { $0.id == item.id }
                                model.saveQuickCommands()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    Button("添加快捷命令") { showAdd = true }
                    Button("恢复默认") {
                        model.quickCommands = DeviceViewModel.defaultQuickCommands
                        model.saveQuickCommands()
                    }
                }

                Section("数据") {
                    Button("清空连接记录（\(model.history.count)）", role: .destructive) {
                        model.clearHistory()
                    }
                }

                Section("功能边界") {
                    Text("iOS 未越狱时无法访问 USB 硬件，因此不支持 USB ADB、Fastboot 刷机、实时 scrcpy 投屏和无线调试配对码配对。支持的是局域网无线 ADB（TCP 5555）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("名称", text: $newName)
                        TextField("命令，例如 input keyevent 3", text: $newCommand)
                            .autocapitalization(.none)
                    }
                    .navigationTitle("新增快捷命令")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("取消") { showAdd = false }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("保存") {
                                guard !newName.isEmpty, !newCommand.isEmpty else { return }
                                model.quickCommands.append(QuickCommand(name: newName, command: newCommand))
                                model.saveQuickCommands()
                                newName = ""
                                newCommand = ""
                                showAdd = false
                            }
                        }
                    }
                }
            }
        }
    }
}
