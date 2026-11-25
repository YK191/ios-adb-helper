import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newCommand = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    aboutCard
                    quickCommandsCard
                    dataCard
                }
                .padding(16)
            }
            .appCanvas()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        Section("命令信息") {
                            TextField("名称，例如 熄屏", text: $newName)
                            TextField("命令，例如 input keyevent 223", text: $newCommand)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    }
                    .tint(AppTheme.mint)
                    .navigationTitle("新增快捷命令")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("取消") { showAdd = false }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("保存") { addCommand() }
                                .disabled(newName.isEmpty || newCommand.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accentGradient)
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    Text("ADB 助手 for iOS")
                        .font(.title3.weight(.bold))
                    Text("通过 Wi-Fi 管理你的 Android 设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(AppTheme.border)

            VStack(spacing: 9) {
                infoRow(icon: "tag", title: "版本", value: "1.1.8")
                infoRow(icon: "key.fill", title: "授权方式", value: "RSA 2048 · 首次连接需手机确认")
                infoRow(icon: "fingerprint", title: "密钥指纹", value: "+6IJs9ePbh2Xs2OpZYVASrfUX2IPyHryESrHqErOzmo=")
            }
        }
        .appCard(padding: 16)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.blue)
                .frame(width: 18)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickCommandsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "我的快捷命令",
                systemImage: "bolt.fill",
                subtitle: "\(model.quickCommands.count) 条 · 点垃圾桶删除"
            )
            if model.quickCommands.isEmpty {
                Text("还没有自定义命令")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(model.quickCommands) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right.2")
                            .font(.caption)
                            .foregroundStyle(AppTheme.mint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.footnote.weight(.semibold))
                            Text(item.command)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button {
                            deleteCommand(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteCommand(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    newName = ""
                    newCommand = ""
                    showAdd = true
                } label: {
                    Label("添加命令", systemImage: "plus")
                }
                .buttonStyle(GradientButtonStyle())

                Button {
                    model.quickCommands = DeviceViewModel.defaultQuickCommands
                    model.saveQuickCommands()
                    model.notify("已恢复默认命令")
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .appCard()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "数据", systemImage: "internaldrive", subtitle: "仅保存在本机", tint: AppTheme.blue)
            Button(role: .destructive) {
                model.clearHistory()
                model.notify("连接记录已清空")
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("清空连接记录（\(model.history.count)）")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.danger)
        }
        .appCard()
    }

    private func deleteCommand(_ item: QuickCommand) {
        model.quickCommands.removeAll { $0.id == item.id }
        model.saveQuickCommands()
        model.notify("已删除快捷命令")
    }

    private func addCommand() {
        guard !newName.isEmpty, !newCommand.isEmpty else { return }
        model.quickCommands.append(QuickCommand(name: newName, command: newCommand))
        model.saveQuickCommands()
        newName = ""
        newCommand = ""
        showAdd = false
    }
}
