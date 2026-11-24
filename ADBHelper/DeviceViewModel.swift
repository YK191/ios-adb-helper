import Foundation
import SwiftUI

final class DeviceViewModel: ObservableObject {
    let device = AdbDevice()

    @Published var host = ""
    @Published var port = "5555"
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var status = "未连接"
    @Published var toast = ""
    @Published var banner = ""
    @Published var deviceInfo: [String: String] = [:]
    @Published var history: [ConnectionRecord] = []
    @Published var quickCommands: [QuickCommand] = []

    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "adb.history"),
           let list = try? JSONDecoder().decode([ConnectionRecord].self, from: data) {
            history = list
        }
        // 旧版本曾预置 9 条快捷命令；升级后只清空一次，之后完全由用户决定。
        if !defaults.bool(forKey: "adb.quick.reset.v2") {
            defaults.removeObject(forKey: "adb.quick")
            defaults.set(true, forKey: "adb.quick.reset.v2")
        }
        if let data = defaults.data(forKey: "adb.quick"),
           let list = try? JSONDecoder().decode([QuickCommand].self, from: data) {
            quickCommands = list
        } else {
            quickCommands = []
        }
    }

    static let defaultQuickCommands: [QuickCommand] = [
        QuickCommand(name: "点亮屏幕", command: "input keyevent 224"),
        QuickCommand(name: "熄灭屏幕", command: "input keyevent 223"),
        QuickCommand(name: "Home", command: "input keyevent 3"),
        QuickCommand(name: "返回", command: "input keyevent 4"),
        QuickCommand(name: "最近任务", command: "input keyevent 187"),
        QuickCommand(name: "音量+", command: "input keyevent 24"),
        QuickCommand(name: "音量-", command: "input keyevent 25"),
        QuickCommand(name: "打开设置", command: "am start -a android.settings.SETTINGS"),
        QuickCommand(name: "重启 SystemUI", command: "killall com.android.systemui"),
    ]

    func ensureConnected() -> Bool {
        if isConnected { return true }
        notify("请先连接设备")
        return false
    }

    func notify(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.toast == text { self?.toast = "" }
        }
    }

    func connect() {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, let portNumber = UInt16(portText) else {
            notify("请填写设备 IP 和端口（默认 5555）")
            return
        }
        status = "正在连接…"
        isConnecting = true
        device.connect(host: address, port: portNumber) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnecting = false
                switch result {
                case .success(let deviceBanner):
                    self.isConnected = true
                    self.banner = deviceBanner
                    self.status = "已连接 \(address):\(portNumber)"
                    self.addHistory(ConnectionRecord(host: address, port: Int(portNumber)))
                    self.notify("连接成功")
                    self.refreshInfo()
                case .failure(let error):
                    self.isConnected = false
                    self.status = "未连接"
                    self.notify(error.localizedDescription)
                }
            }
        }
    }

    func disconnect() {
        device.disconnect()
        isConnecting = false
        isConnected = false
        status = "未连接"
        banner = ""
        deviceInfo = [:]
        notify("已断开连接")
    }

    func refreshInfo() {
        guard ensureConnected() else { return }
        device.deviceInfo { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info): self?.deviceInfo = info
                case .failure(let error): self?.notify(error.localizedDescription)
                }
            }
        }
    }

    func run(_ command: String, success: String = "命令已执行") {
        guard ensureConnected() else { return }
        device.shell(command) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.notify(success)
                case .failure(let error): self?.notify(error.localizedDescription)
                }
            }
        }
    }

    func saveQuickCommands() {
        if let data = try? JSONEncoder().encode(quickCommands) {
            defaults.set(data, forKey: "adb.quick")
        }
    }

    private func addHistory(_ record: ConnectionRecord) {
        history.removeAll { $0.id == record.id }
        history.insert(record, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: "adb.history")
        }
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: "adb.history")
    }
}
