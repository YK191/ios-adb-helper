import SwiftUI

struct ShellView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var command = ""
    @State private var output = "连接设备后输入 adb shell 命令，例如：\ngetprop ro.product.model\n pm list packages -3"
    @State private var commandHistory: [String] = []
    @State private var showQuick = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                ScrollView {
                    Text(output)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    TextField("shell 命令", text: $command)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit(execute)
                    Button("执行", action: execute)
                        .buttonStyle(.borderedProminent)
                        .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack {
                    Button("快捷命令") { showQuick = true }
                    Button("复制输出") { UIPasteboard.general.string = output }
                    Button("清空") { output = "" }
                    Spacer()
                    if !commandHistory.isEmpty {
                        Menu("历史") {
                            ForEach(Array(commandHistory.suffix(12)), id: \.self) { item in
                                Button(item) { command = item }
                            }
                        }
                    }
                }
                .font(.footnote)
            }
            .padding()
            .navigationTitle("终端")
            .toolbar {
                Button("日志") { loadLogcat() }
            }
            .sheet(isPresented: $showQuick) { quickCommandSheet }
        }
    }

    private var quickCommandSheet: some View {
        NavigationStack {
            List {
                Section("内置快捷命令") {
                    ForEach(DeviceViewModel.defaultQuickCommands) { item in
                        Button {
                            command = item.command
                            showQuick = false
                            execute()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(item.command).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !model.quickCommands.isEmpty {
                    Section("我的快捷命令") {
                        ForEach(model.quickCommands) { item in
                            Button {
                                command = item.command
                                showQuick = false
                                execute()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.command).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("快捷命令")
            .toolbar {
                Button("完成") { showQuick = false }
            }
        }
    }

    private func loadLogcat() {
        guard model.ensureConnected() else { return }
        output = "正在读取最近日志…\n"
        model.device.logcat(lines: 300) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text): output = text.isEmpty ? "(日志为空)" : text
                case .failure(let error): output = "读取失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func execute() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, model.ensureConnected() else { return }
        commandHistory.append(text)
        if commandHistory.count > 50 { commandHistory.removeFirst() }
        output = "$ \(text)\n"
        model.device.shell(text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    output += value
                    if value.isEmpty { output += "(无输出)\n" }
                case .failure(let error):
                    output += "错误：\(error.localizedDescription)\n"
                }
            }
        }
    }
}
