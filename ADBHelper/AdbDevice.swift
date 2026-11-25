import Foundation
import Combine

struct AdbStream {
    let localId: UInt32
    let remoteId: UInt32
}

struct SyncMessage {
    let id: String
    let size: UInt32
    let fields: [UInt32]
    let data: Data
}

/// FileSync packets are [4-byte ASCII id][4-byte little-endian size][payload].
/// DENT and STAT carry three extra UInt32 fields inside the payload area.
private final class SyncChannel {
    unowned let device: AdbDevice
    let stream: AdbStream
    var buffer = Data()

    init(device: AdbDevice, stream: AdbStream) {
        self.device = device
        self.stream = stream
    }

    func send(id: String, data: Data = Data(), size: UInt32? = nil) throws {
        var payload = Data(id.utf8)
        adbAppendLE(size ?? UInt32(data.count), to: &payload)
        payload.append(data)
        try device.socket.sendPacket(
            command: AdbCommand.wrte,
            arg0: stream.localId,
            arg1: stream.remoteId,
            payload: payload
        )
        let reply = try device.takePacket(forLocalId: stream.localId)
        guard reply.command == AdbCommand.okay else {
            throw AdbError.device(String(decoding: reply.payload, as: UTF8.self))
        }
    }

    func receive() throws -> SyncMessage {
        while true {
            if buffer.count >= 8 {
                let id = String(decoding: buffer.prefix(4), as: UTF8.self)
                let size = adbReadLE(buffer, at: 4)
                let requiredHeader = id == "DENT" ? 20 : (id == "STAT" ? 16 : 8)

                if buffer.count >= requiredHeader {
                    var headerLength = 8
                    var payloadLength = Int(size)
                    var fields: [UInt32] = []

                    if id == "DENT" || id == "STAT" {
                        headerLength = requiredHeader
                        fields = [adbReadLE(buffer, at: 4), adbReadLE(buffer, at: 8), adbReadLE(buffer, at: 12)]
                        payloadLength = id == "DENT" ? Int(adbReadLE(buffer, at: 16)) : 0
                    }

                    if buffer.count >= headerLength + payloadLength {
                        let data = Data(buffer.dropFirst(headerLength).prefix(payloadLength))
                        buffer.removeSubrange(0..<(headerLength + payloadLength))
                        return SyncMessage(id: id, size: size, fields: fields, data: data)
                    }
                }
            }

            let packet = try device.takePacket(forLocalId: stream.localId)
            if packet.command == AdbCommand.wrte {
                try device.socket.sendPacket(
                    command: AdbCommand.okay,
                    arg0: stream.localId,
                    arg1: stream.remoteId
                )
                buffer.append(packet.payload)
            } else if packet.command == AdbCommand.clse {
                throw AdbError.protocolError("文件通道已关闭")
            } else if packet.command == AdbCommand.fail {
                throw AdbError.device(String(decoding: packet.payload, as: UTF8.self))
            }
        }
    }
}

final class AdbDevice: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var status = "未连接"

    fileprivate let socket = AdbSocket()
    private let queue = DispatchQueue(label: "com.adbhelper.adb", qos: .userInitiated)
    private var nextLocalId: UInt32 = 1
    private var pendingPackets: [AdbPacket] = []
    /// 录像专用通道：必须一直开着，screenrecord 才不会因为 SIGHUP 被杀。
    private var recordingStream: AdbStream?

    // MARK: - Connection

    func connect(host: String, port: UInt16, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                let banner = try self.connectSync(host: host, port: port)
                // 清理旧版本或异常退出可能遗留在设备上的录像临时文件。
                try? self.shellText("rm -f /data/local/tmp/adbhelper-*.mp4 /data/local/tmp/Screenrecord_*.mp4 /sdcard/adbhelper-*.mp4", timeout: 10)
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.status = "已连接 \(host):\(port)"
                    completion(.success(banner))
                }
            } catch {
                self.socket.close()
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.status = "连接失败"
                    completion(.failure(error))
                }
            }
        }
    }

    func disconnect() {
        queue.async {
            self.recordingStream = nil
            self.socket.close()
            self.pendingPackets.removeAll()
            DispatchQueue.main.async {
                self.isConnected = false
                self.status = "未连接"
            }
        }
    }

    private func connectSync(host: String, port: UInt16) throws -> String {
        try socket.connect(host: host, port: port)
        try socket.sendPacket(
            command: AdbCommand.cnxn,
            arg0: AdbCommand.version,
            arg1: AdbCommand.maxPayload,
            payload: Data("host::\0".utf8)
        )

        var packet = try socket.readPacket()
        if packet.command == AdbCommand.cnxn { return banner(from: packet.payload) }

        // Modern adbd requires an RSA signature before opening services.
        guard packet.command == AdbCommand.auth, packet.arg0 == AdbCommand.authToken else {
            throw AdbError.authentication("设备响应异常：\(adbName(packet.command))")
        }
        let signature = try AdbAuth.sign(packet.payload)
        try socket.sendPacket(
            command: AdbCommand.auth,
            arg0: AdbCommand.authSignature,
            payload: signature
        )

        packet = try socket.readPacket()
        if packet.command == AdbCommand.cnxn { return banner(from: packet.payload) }
        guard packet.command == AdbCommand.auth, packet.arg0 == AdbCommand.authToken else {
            throw AdbError.authentication("密钥签名未被接受")
        }

        try socket.sendPacket(
            command: AdbCommand.auth,
            arg0: AdbCommand.authPublicKey,
            payload: AdbAuth.publicKey
        )
        socket.setReadTimeout(120) // user must confirm the RSA dialog on the Android device
        packet = try socket.readPacket()
        socket.setReadTimeout(30)
        guard packet.command == AdbCommand.cnxn else {
            throw AdbError.authentication("请检查手机上的 USB/无线调试授权弹窗")
        }
        return banner(from: packet.payload)
    }

    private func banner(from data: Data) -> String {
        var bytes = Array(data)
        if bytes.last == 0 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Async helpers

    private func perform<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        queue.async {
            do {
                let value = try work()
                DispatchQueue.main.async { completion(.success(value)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func requireConnection() throws {
        guard socket.isOpen else { throw AdbError.connection("请先连接设备") }
    }

    /// Read a packet, ignoring any packet that belongs to another stream.
    /// Packets from other streams are kept for their own readers instead of
    /// being mistaken for an OPEN reply (a common cause of "无法打开服务").
    fileprivate func takePacket(forLocalId localId: UInt32? = nil) throws -> AdbPacket {
        while true {
            if !pendingPackets.isEmpty {
                if let wanted = localId {
                    if let index = pendingPackets.firstIndex(where: {
                        $0.arg1 == wanted || $0.arg0 == wanted
                    }) {
                        return pendingPackets.remove(at: index)
                    }
                } else {
                    return pendingPackets.removeFirst()
                }
            }
            let packet = try socket.readPacket()
            if let wanted = localId, packet.arg1 != wanted, packet.arg0 != wanted {
                pendingPackets.append(packet)
                continue
            }
            return packet
        }
    }

    // MARK: - Low-level services

    private func openService(_ service: String) throws -> AdbStream {
        try requireConnection()
        let localId = nextLocalId
        nextLocalId = nextLocalId &+ 1
        if nextLocalId == 0 { nextLocalId = 1 }

        try socket.sendPacket(
            command: AdbCommand.open,
            arg0: localId,
            arg1: 0,
            payload: Data((service + "\0").utf8)
        )
        let reply = try takePacket(forLocalId: localId)
        if reply.command == AdbCommand.fail {
            throw AdbError.device(String(decoding: reply.payload, as: UTF8.self))
        }
        guard reply.command == AdbCommand.okay else {
            throw AdbError.protocolError("无法打开服务 \(service)（收到 \(adbName(reply.command))）")
        }
        // Standard adbd echoes our id in arg1 and its own id in arg0.
        // Some ROMs swap them; accept both so every service keeps working.
        let remoteId: UInt32
        if reply.arg1 == localId {
            remoteId = reply.arg0
        } else if reply.arg0 == localId {
            remoteId = reply.arg1
        } else {
            remoteId = reply.arg0 != 0 ? reply.arg0 : 1
        }
        return AdbStream(localId: localId, remoteId: remoteId)
    }

    private func closeStream(_ stream: AdbStream) {
        try? socket.sendPacket(command: AdbCommand.clse, arg0: stream.localId, arg1: stream.remoteId)
        socket.setReadTimeout(2)
        for _ in 0..<3 {
            guard let packet = try? takePacket(forLocalId: stream.localId) else { break }
            if packet.command == AdbCommand.clse { break }
            pendingPackets.insert(packet, at: 0)
            break
        }
        socket.setReadTimeout(30)
    }

    private func serviceData(_ service: String, command: String, timeout: Double = 30) throws -> Data {
        socket.setReadTimeout(timeout)
        defer { socket.setReadTimeout(30) }
        let stream = try openService("\(service):\(command)")
        var closed = false
        defer {
            if !closed {
                try? socket.sendPacket(command: AdbCommand.clse, arg0: stream.localId, arg1: stream.remoteId)
            }
        }

        var output = Data()
        while true {
            let packet = try takePacket(forLocalId: stream.localId)
            if packet.command == AdbCommand.wrte {
                output.append(packet.payload)
                try socket.sendPacket(
                    command: AdbCommand.okay,
                    arg0: stream.localId,
                    arg1: stream.remoteId
                )
            } else if packet.command == AdbCommand.clse {
                try? socket.sendPacket(
                    command: AdbCommand.clse,
                    arg0: stream.localId,
                    arg1: stream.remoteId
                )
                closed = true
                break
            } else if packet.command == AdbCommand.fail {
                throw AdbError.device(String(decoding: packet.payload, as: UTF8.self))
            } else if packet.command == AdbCommand.auth {
                throw AdbError.authentication("认证状态丢失，请重新连接")
            }
        }
        return output
    }

    private func shellText(_ command: String, timeout: Double = 30) throws -> String {
        let data = try serviceData("shell", command: command, timeout: timeout)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Public commands

    func deviceInfo(completion: @escaping (Result<[String: String], Error>) -> Void) {
        perform({ try self.readDeviceInfo() }, completion: completion)
    }

    private func readDeviceInfo() throws -> [String: String] {
        let text = try shellText("getprop")
        var result: [String: String] = [:]
        let pattern = #"^\[([^\]]+)\]: \[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(line)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else { continue }
            result[String(line[keyRange])] = String(line[valueRange])
        }

        // Derived: verified boot state + bootloader lock flag
        if let state = result["ro.boot.verifiedbootstate"], !state.isEmpty {
            let flag = result["ro.boot.flash.locked"] ?? ""
            let lockText = flag == "1" ? "已锁" : (flag == "0" ? "已解锁" : "")
            result["adbhelper.bootstate"] = lockText.isEmpty ? state : "\(state) · \(lockText)"
        }

        // Extra read-only probes: kernel, SELinux, storage. Best effort so a
        // single unsupported command never breaks the whole info screen.
        let probe = "echo \"APH_KERNEL=$(uname -r 2>/dev/null)\"; "
            + "echo \"APH_SELINUX=$(getenforce 2>/dev/null)\"; "
            + "echo \"APH_STORAGE=$(df -h /data 2>/dev/null | tail -1)\""
        if let extra = try? shellText(probe, timeout: 20) {
            for raw in extra.split(whereSeparator: { $0.isNewline }) {
                let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<eq])
                let value = String(line[line.index(after: eq)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                switch key {
                case "APH_KERNEL":
                    result["adbhelper.kernel"] = value
                case "APH_SELINUX":
                    result["adbhelper.selinux"] = value
                case "APH_STORAGE":
                    let columns = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    if columns.count >= 4 {
                        // df: Filesystem Size Used Avail Use% Mounted
                        result["adbhelper.storage"] = "可用 \(columns[3]) · 已用 \(columns[2]) · 共 \(columns[1])"
                    } else {
                        result["adbhelper.storage"] = value
                    }
                default:
                    break
                }
            }
        }
        return result
    }

    func shell(_ command: String, completion: @escaping (Result<String, Error>) -> Void) {
        perform({ try self.shellText(command) }, completion: completion)
    }

    func logcat(lines: Int, completion: @escaping (Result<String, Error>) -> Void) {
        perform({ try self.shellText("logcat -d -t \(lines)", timeout: 45) }, completion: completion)
    }

    func screenshot(completion: @escaping (Result<Data, Error>) -> Void) {
        perform({
            let raw: Data
            do {
                raw = try self.serviceData("exec-out", command: "screencap -p", timeout: 40)
            } catch {
                raw = try self.serviceData("shell", command: "screencap -p", timeout: 40)
            }
            var data = raw
            let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
            if !data.starts(with: png) {
                // Some devices rewrite LF to CRLF on shell streams.
                var cleaned = Data()
                var index = 0
                while index < data.count {
                    if index + 1 < data.count && data[index] == 0x0d && data[index + 1] == 0x0a {
                        cleaned.append(0x0a)
                        index += 2
                    } else {
                        cleaned.append(data[index])
                        index += 1
                    }
                }
                data = cleaned
            }
            guard data.starts(with: png) else { throw AdbError.device("截图数据不是有效的 PNG") }
            return data
        }, completion: completion)
    }

    // MARK: - Screen recording

    /// 录像方式与 atvTools 一致：`screenrecord` 跑在一个「常开」的 shell 通道里，
    /// 前景执行（不带 `&`）。旧实现用 `screenrecord ... &` 后台启动，adb shell
    /// 通道读到 EOF 关闭后 adbd 会给整个进程组发 SIGHUP，进程在几百毫秒内被杀，
    /// 所以永远返回「启动失败」。保持通道打开，进程就一直活着，随时可 SIGINT 停止。
    func startScreenRecording(completion: @escaping (Result<ScreenRecording, Error>) -> Void) {
        perform({
            self.closeRecordingStream()

            // atvTools 的做法：先按设备默认分辨率启动，失败再降级到 1280x720；
            // 若临时目录不可写，再退到 /sdcard。每次尝试都用新文件名，避免 File exists。
            let base = AdbDevice.recordBaseName()
            let attempts: [(option: String, directory: String)] = [
                ("", "/data/local/tmp"),
                ("--size 1280x720", "/data/local/tmp"),
                ("--size 1280x720", "/sdcard"),
            ]
            var lastError: Error?
            for attempt in attempts {
                let remote = "\(attempt.directory)/\(base).mp4"
                do {
                    return try self.launchScreenRecord(remote: remote, option: attempt.option)
                } catch {
                    lastError = error
                    self.closeRecordingStream()
                    // 清掉这次尝试可能在设备上留下的空文件
                    _ = try? self.shellText("rm -f \(remote)", timeout: 10)
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            throw lastError ?? AdbError.device("设备不支持 screenrecord")
        }, completion: completion)
    }

    private static func recordBaseName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Screenrecord_\(formatter.string(from: Date()))"
    }

    /// 在常开通道里前台启动 screenrecord，并把 pid 返回给上层。
    private func launchScreenRecord(remote: String, option: String) throws -> ScreenRecording {
        _ = try? self.shellText("rm -f \(remote)", timeout: 10)

        let args = option.isEmpty ? "" : "\(option) "
        // exec 让 screenrecord 直接接管这个 shell 进程的 pid，
        // 之后用 `kill -INT <pid>` 就能让它写完 moov 再退出。
        let command = "echo ADBH_PID:$$; exec screenrecord \(args)\(remote)"

        socket.setReadTimeout(4)
        defer { socket.setReadTimeout(30) }
        let stream = try openService("shell:\(command)")

        var text = ""
        var pid: Int?
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            guard let chunk = try? readStreamChunk(stream) else { break }
            text += String(decoding: chunk, as: UTF8.self)
            if pid == nil, let range = text.range(of: "ADBH_PID:") {
                let digits = text[range.upperBound...].prefix(while: { $0.isNumber })
                if !digits.isEmpty {
                    pid = Int(digits)
                    break
                }
            }
        }

        guard let pid = pid else {
            let detail = AdbDevice.cleanMessage(text + drainStream(stream))
            throw AdbError.device(detail.isEmpty ? "screenrecord 没有响应" : detail)
        }

        // 编码器初始化需要一点时间：确认进程没有立刻退出，并且文件已经开始写入。
        var alive = true
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            let state = (try? self.shellText("if kill -0 \(pid) 2>/dev/null; then echo alive; else echo gone; fi")) ?? ""
            if state.contains("gone") { alive = false; break }
            if AdbDevice.byteCount((try? self.shellText("wc -c < \(remote) 2>/dev/null")) ?? "") > 0 { break }
        }

        if !alive {
            let detail = AdbDevice.cleanMessage(text + drainStream(stream))
            closeStream(stream)
            throw AdbError.device(detail.isEmpty
                ? "screenrecord 进程退出，设备可能不支持录像或没有存储空间"
                : "screenrecord 启动失败：\(detail)")
        }

        recordingStream = stream
        return ScreenRecording(pid: pid, remotePath: remote, logPath: "", startedAt: Date())
    }

    /// Stop a recording gracefully, wait for the MP4 to be finalized, then
    /// pull it into the app's Documents directory (visible in Files).
    func stopScreenRecording(_ recording: ScreenRecording, completion: @escaping (Result<URL, Error>) -> Void) {
        perform({
            // 无论拉取或写入是否失败，都尽力删掉设备端临时文件。
            defer {
                self.closeRecordingStream()
                _ = try? self.shellText("rm -f \(recording.remotePath)", timeout: 10)
            }

            // SIGINT 是 screenrecord 的「正常停止」，它会把 moov 写完再退出。
            _ = try? self.shellText("kill -INT \(recording.pid) 2>/dev/null", timeout: 10)
            let deadline = Date().addingTimeInterval(10)
            var stopped = false
            while Date() < deadline {
                let state = (try? self.shellText("if kill -0 \(recording.pid) 2>/dev/null; then echo alive; else echo gone; fi")) ?? "gone"
                if state.contains("gone") { stopped = true; break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            if !stopped {
                _ = try? self.shellText("kill -TERM \(recording.pid) 2>/dev/null", timeout: 10)
                Thread.sleep(forTimeInterval: 0.6)
            }

            // 等文件大小稳定，确保 moov 已经落盘再拉取。
            var lastSize = -1
            for _ in 0..<20 {
                let size = AdbDevice.byteCount((try? self.shellText("wc -c < \(recording.remotePath) 2>/dev/null")) ?? "")
                if size > 0 && size == lastSize { break }
                lastSize = size
                Thread.sleep(forTimeInterval: 0.3)
            }

            self.closeRecordingStream()

            let data = try self.pullFileSync(recording.remotePath)
            guard !data.isEmpty else {
                throw AdbError.device("录像文件为空，设备可能不支持录像")
            }
            let directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let name = (recording.remotePath as NSString).lastPathComponent
            let destination = directory.appendingPathComponent(name)
            try data.write(to: destination, options: .atomic)
            return destination
        }, completion: completion)
    }

    // MARK: - Recording stream plumbing

    /// 从指定通道读一块数据；通道关闭或读超时会抛出，调用方据此判断。
    private func readStreamChunk(_ stream: AdbStream) throws -> Data {
        while true {
            let packet = try takePacket(forLocalId: stream.localId)
            if packet.command == AdbCommand.wrte {
                try? socket.sendPacket(
                    command: AdbCommand.okay,
                    arg0: stream.localId,
                    arg1: stream.remoteId
                )
                return packet.payload
            } else if packet.command == AdbCommand.clse {
                throw AdbError.connection("通道已关闭")
            } else if packet.command == AdbCommand.fail {
                throw AdbError.device(String(decoding: packet.payload, as: UTF8.self))
            }
        }
    }

    /// 短超时地把通道里剩余的报错信息读出来（最多约 4KB）。
    private func drainStream(_ stream: AdbStream, timeout: Double = 0.5) -> String {
        socket.setReadTimeout(timeout)
        defer { socket.setReadTimeout(30) }
        var text = ""
        for _ in 0..<8 {
            guard let chunk = try? readStreamChunk(stream) else { break }
            text += String(decoding: chunk, as: UTF8.self)
            if text.count > 4000 { break }
        }
        return text
    }

    private func closeRecordingStream() {
        guard let stream = recordingStream else { return }
        recordingStream = nil
        try? socket.sendPacket(command: AdbCommand.clse, arg0: stream.localId, arg1: stream.remoteId)
        // 清掉这条通道上残留的包，避免污染后续命令的读取。
        socket.setReadTimeout(1)
        for _ in 0..<8 {
            guard let packet = try? takePacket(forLocalId: stream.localId) else { break }
            if packet.command == AdbCommand.clse { break }
        }
        socket.setReadTimeout(30)
    }

    private static func byteCount(_ text: String) -> Int {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func cleanMessage(_ raw: String) -> String {
        let lines = raw.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("ADBH_PID:") }
        return lines.suffix(3).joined(separator: " ")
    }

    func listPackages(system: Bool, completion: @escaping (Result<[AppInfo], Error>) -> Void) {
        perform({
            let flag = system ? "-s" : "-3"
            let text = try self.shellText("pm list packages \(flag)")
            var apps = text.split(whereSeparator: { $0.isNewline }).compactMap { line -> AppInfo? in
                let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.hasPrefix("package:") else { return nil }
                return AppInfo(packageName: String(value.dropFirst("package:".count)), label: nil)
            }
            // Resolve Chinese labels in one batched shell command so the list
            // stays fast. nonLocalizedLabel holds the localized app name.
            if !apps.isEmpty {
                let packages = apps.map(\.packageName).joined(separator: " ")
                let labelText = try? self.shellText(
                    "for p in \(packages); do L=$(pm dump $p 2>/dev/null | grep -m1 'nonLocalizedLabel=' | sed 's/.*nonLocalizedLabel=//'); echo \"$p|$L\"; done",
                    timeout: 90
                )
                var labels: [String: String] = [:]
                labelText?.split(whereSeparator: { $0.isNewline }).forEach { line in
                    let parts = String(line).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else { return }
                    let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty, name != "null", !name.hasPrefix("0x") {
                        labels[String(parts[0])] = name
                    }
                }
                apps = apps.map { app in
                    var copy = app
                    copy.label = labels[app.packageName]
                    return copy
                }
            }
            return apps
        }, completion: completion)
    }

    func appAction(_ action: String, package: String, completion: @escaping (Result<String, Error>) -> Void) {
        let commands: [String: String] = [
            "launch": "monkey -p \(package) -c android.intent.category.LAUNCHER 1",
            "stop": "am force-stop \(package)",
            "uninstall": "pm uninstall \(package)",
            "freeze": "pm disable-user --user 0 \(package)",
            "unfreeze": "pm enable \(package)",
            "clear": "pm clear \(package)",
        ]
        guard let command = commands[action] else {
            completion(.failure(AdbError.protocolError("未知操作")))
            return
        }
        perform({ try self.shellText(command) }, completion: completion)
    }

    func reboot(mode: String, completion: @escaping (Result<String, Error>) -> Void) {
        let command = mode == "normal" ? "reboot" : "reboot \(mode)"
        perform({ try self.shellText(command) }, completion: completion)
    }

    func listFiles(path: String, completion: @escaping (Result<[RemoteFile], Error>) -> Void) {
        perform({
            do {
                return try self.listFilesSync(path)
            } catch {
                // sync LIST is denied on many system paths (e.g. /data).
                // Fall back to `ls -la` over the shell service.
                return try self.listFilesShell(path)
            }
        }, completion: completion)
    }

    /// Fallback listing via `ls -la`, used when the sync protocol has no
    /// permission for the directory (common for /data and other root paths).
    private func listFilesShell(_ path: String) throws -> [RemoteFile] {
        let safe = path.replacingOccurrences(of: "\"", with: "\\\"")
        let text = try shellText("ls -la \"\(safe)\" 2>/dev/null", timeout: 30)
        var result: [RemoteFile] = []
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(raw)
            let columns = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard columns.count >= 8 else { continue }
            let permissions = columns[0]
            guard permissions.count >= 10 else { continue }
            let name = columns[7...].joined(separator: " ")
            guard name != "." && name != ".." else { continue }
            var mode: UInt32 = permissions.hasPrefix("d") ? 0o40755 : 0o100644
            let chars = Array(permissions)
            let ownerRead = chars[1] != "-" ? UInt32(0o400) : 0
            let ownerWrite = chars[2] != "-" ? UInt32(0o200) : 0
            mode |= ownerRead | ownerWrite
            let size = UInt32(columns[4]) ?? 0
            let fullPath = path.hasSuffix("/") ? path + name : path + "/" + name
            result.append(RemoteFile(name: name, path: fullPath, mode: mode, size: size, mtime: 0))
        }
        return result.sorted { $0.name < $1.name }
    }

    private func listFilesSync(_ path: String) throws -> [RemoteFile] {
        let stream = try openService("sync:")
        defer { closeStream(stream) }
        let channel = SyncChannel(device: self, stream: stream)
        try channel.send(id: "LIST", data: Data(path.utf8))

        var result: [RemoteFile] = []
        while true {
            let message = try channel.receive()
            if message.id == "DENT" {
                guard message.fields.count >= 3 else { continue }
                let name = String(decoding: message.data, as: UTF8.self)
                guard name != "." && name != ".." else { continue }
                let fullPath = path.hasSuffix("/") ? path + name : path + "/" + name
                result.append(RemoteFile(
                    name: name,
                    path: fullPath,
                    mode: message.fields[0],
                    size: message.fields[1],
                    mtime: message.fields[2]
                ))
            } else if message.id == "DONE" {
                break
            } else if message.id == "FAIL" {
                throw AdbError.device(String(decoding: message.data, as: UTF8.self))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    func pushFile(from url: URL, to remotePath: String, completion: @escaping (Result<String, Error>) -> Void) {
        perform({
            try self.pushFileSync(from: url, to: remotePath)
            return "已上传 \(remotePath)"
        }, completion: completion)
    }

    private func pushFileSync(from url: URL, to remotePath: String, progress: ((Double) -> Void)? = nil) throws {
        let stream = try openService("sync:")
        defer { closeStream(stream) }
        let channel = SyncChannel(device: self, stream: stream)
        let mode: UInt32 = 0o100644
        let fileInfo = "\(remotePath),\(mode)"
        try channel.send(id: "SEND", data: Data(fileInfo.utf8))

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.doubleValue ?? 0
        var sent: Double = 0
        while true {
            let chunk = try handle.read(upToCount: 60 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try channel.send(id: "DATA", data: chunk)
            sent += Double(chunk.count)
            if total > 0 { progress?(min(sent / total, 1)) }
        }
        progress?(1)
        let mtime = UInt32(Date().timeIntervalSince1970)
        try channel.send(id: "DONE", size: mtime)

        let reply = try channel.receive()
        guard reply.id == "OKAY" else {
            throw AdbError.device(String(decoding: reply.data, as: UTF8.self))
        }
    }

    func pullFile(from remotePath: String, completion: @escaping (Result<URL, Error>) -> Void) {
        perform({
            let data = try self.pullFileSync(remotePath)
            guard !data.isEmpty else {
                throw AdbError.device("文件为空或没有读取权限（\(remotePath)）")
            }
            let directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            var name = (remotePath as NSString).lastPathComponent
            if name.isEmpty || name == "/" || name == "." || name == ".." {
                name = "downloaded.file"
            }
            // iOS 文件名不允许冒号，Android 则允许，替换掉避免写入失败。
            name = name.replacingOccurrences(of: ":", with: "_")
            let destination = directory.appendingPathComponent(name)
            try data.write(to: destination, options: .atomic)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw AdbError.protocolError("文件写入失败")
            }
            return destination
        }, completion: completion)
    }

    private func pullFileSync(_ remotePath: String) throws -> Data {
        let stream = try openService("sync:")
        defer { closeStream(stream) }
        let channel = SyncChannel(device: self, stream: stream)
        try channel.send(id: "RECV", data: Data(remotePath.utf8))

        var output = Data()
        while true {
            let message = try channel.receive()
            if message.id == "DATA" {
                output.append(message.data)
            } else if message.id == "DONE" {
                break
            } else if message.id == "FAIL" {
                throw AdbError.device(String(decoding: message.data, as: UTF8.self))
            }
        }
        return output
    }

    func installApk(from url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        installApk(from: url, progress: nil, completion: completion)
    }

    /// Install an APK, reporting progress: 0–0.9 while pushing the file,
    /// 0.9–1.0 while the package manager installs it.
    func installApk(from url: URL, progress: ((Double) -> Void)?, completion: @escaping (Result<String, Error>) -> Void) {
        perform({
            let name = "adbhelper-\(UUID().uuidString).apk"
            let remote = "/data/local/tmp/\(name)"
            defer { _ = try? self.shellText("rm -f \(remote)") }
            try self.pushFileSync(from: url, to: remote) { fraction in
                progress?(fraction * 0.9)
            }
            progress?(0.92)
            let output = try self.shellText("pm install -r \(remote)", timeout: 180)
            progress?(1)
            if output.localizedCaseInsensitiveContains("success") { return output }
            throw AdbError.device(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }, completion: completion)
    }
}
