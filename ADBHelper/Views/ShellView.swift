import SwiftUI

struct ShellView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var command = ""
    @State private var lines: [OutputLine] = [
        OutputLine(
            text: "连接设备后输入 adb shell 命令，例如：\n  getprop ro.product.model\n  pm list packages -3",
            kind: .hint
        )
    ]
    @State private var commandHistory: [String] = []
    @State private var showQuick = false

    private enum OutputKind: Equatable {
        case hint, command, result, error, info
    }

    private struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: OutputKind
    }

    private func color(for kind: OutputKind) -> Color {
        switch kind {
        case .hint: return Color.white.opacity(0.38)
        case .command: return AppTheme.mint
        case .result: return Color(0xD6F5E9)
        case .error: return AppTheme.danger
        case .info: return AppTheme.blue
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                terminalPanel

                commandBar

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        toolButton("zap", "快捷命令") { showQuick = true }
                        toolButton("doc.on.doc", "复制") { copyOutput() }
                        toolButton("clipboard", "粘贴") { paste() }
                        toolButton("trash", "清空") { lines = [] }
                        toolButton("doc.text.magnifyingglass", "日志") { loadLogcat() }
                        if !commandHistory.isEmpty {
                            Menu {
                                ForEach(Array(commandHistory.suffix(12)), id: \.self) { item in
                                    Button(item) { command = item }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text("历史")
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.blue)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(AppTheme.blue.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(16)
            .appCanvas()
            .navigationTitle("Shell 终端")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showQuick) { quickCommandSheet }
        }
    }

    private var terminalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([("a", Color(0xFF6B6B)), ("b", Color(0xFFC75B)), ("c", Color(0x5BD68B))], id: \.0) { _, color in
                    Circle().fill(color).frame(width: 9, height: 9)
                }
                Spacer()
                Text("shell@android")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                StatusPill(connected: model.isConnected, text: model.isConnected ? "ONLINE" : "OFFLINE")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.045))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(
                                .footnote,
                                design: .monospaced,
                                weight: line.kind == .command ? .semibold : .regular
                            ))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.mint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: AppTheme.mint.opacity(0.07), radius: 16, y: 6)
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            Text("$")
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(AppTheme.mint)
            TextField("输入命令…", text: $command)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.footnote, design: .monospaced))
                .onSubmit(execute)
            Button {
                execute()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accentGradient, in: Circle())
            }
            .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func toolButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.mint)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(AppTheme.mint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func copyOutput() {
        let all = lines.map(\.text).joined()
        guard !all.isEmpty else { return }
        UIPasteboard.general.string = all
        model.notify("终端内容已复制")
    }

    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            model.notify("剪贴板为空")
            return
        }
        command = text
    }

    private var quickCommandSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    commandSection("内置命令", DeviceViewModel.defaultQuickCommands)
                    if !model.quickCommands.isEmpty {
                        commandSection("我的命令", model.quickCommands)
                    }
                }
                .padding(16)
            }
            .appCanvas()
            .navigationTitle("快捷命令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { showQuick = false }
            }
        }
    }

    private func commandSection(_ title: String, _ items: [QuickCommand]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, systemImage: "bolt.fill", subtitle: "\(items.count) 条命令")
            ForEach(items) { item in
                Button {
                    command = item.command
                    showQuick = false
                    execute()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(item.command)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(AppTheme.mint)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .appCard()
    }

    private func loadLogcat() {
        guard model.ensureConnected() else { return }
        lines = [OutputLine(text: "正在读取最近日志…\n", kind: .info)]
        model.device.logcat(lines: 300) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    lines = [OutputLine(text: text.isEmpty ? "(日志为空)" : text, kind: .result)]
                case .failure(let error):
                    lines = [OutputLine(text: "读取失败：\(error.localizedDescription)", kind: .error)]
                }
            }
        }
    }

    private func execute() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, model.ensureConnected() else { return }
        commandHistory.append(text)
        if commandHistory.count > 50 { commandHistory.removeFirst() }
        command = ""
        // Remove the initial hint once the user runs a command.
        lines.removeAll { $0.kind == .hint }
        lines.append(OutputLine(text: "$ \(text)\n", kind: .command))
        model.device.shell(text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    lines.append(OutputLine(text: value.isEmpty ? "(无输出)\n" : value, kind: .result))
                case .failure(let error):
                    lines.append(OutputLine(text: "错误：\(error.localizedDescription)\n", kind: .error))
                }
            }
        }
    }
}
