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
        let reply = try device.takePacket()
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

            let packet = try device.takePacket()
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

    // MARK: - Connection

    func connect(host: String, port: UInt16, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                let banner = try self.connectSync(host: host, port: port)
                // 清理旧版本或异常退出可能遗留在设备上的录像临时文件。
                try? self.shellText("rm -f /data/local/tmp/adbhelper-*.mp4 /sdcard/adbhelper-*.mp4", timeout: 10)
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

    fileprivate func takePacket() throws -> AdbPacket {
        if !pendingPackets.isEmpty { return pendingPackets.removeFirst() }
        return try socket.readPacket()
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
        let reply = try takePacket()
        if reply.command == AdbCommand.fail {
            throw AdbError.device(String(decoding: reply.payload, as: UTF8.self))
        }
        guard reply.command == AdbCommand.okay, reply.arg1 == localId else {
            throw AdbError.protocolError("无法打开服务 \(service)")
        }
        return AdbStream(localId: localId, remoteId: reply.arg0)
    }

    private func closeStream(_ stream: AdbStream) {
        try? socket.sendPacket(command: AdbCommand.clse, arg0: stream.localId, arg1: stream.remoteId)
        socket.setReadTimeout(2)
        for _ in 0..<3 {
            guard let packet = try? takePacket() else { break }
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
            let packet = try takePacket()
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

    /// Start `screenrecord` as a background process and return its PID so the
    /// recording can be stopped at any time with SIGINT.
    func startScreenRecording(completion: @escaping (Result<ScreenRecording, Error>) -> Void) {
        // 临时文件放在 /data/local/tmp（不进入相册/媒体库），停止后一定会清理。
        let name = "adbhelper-\(Int(Date().timeIntervalSince1970)).mp4"
        let remote = "/data/local/tmp/\(name)"
        perform({
            let text = try self.shellText("screenrecord \(remote) >/dev/null 2>&1 & echo $!", timeout: 15)
            let lines = text.split(whereSeparator: { $0.isNewline }).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let pidLine = lines.last(where: { !$0.isEmpty }), let pid = Int(pidLine), pid > 0 else {
                try? self.shellText("rm -f \(remote)")
                throw AdbError.device("无法启动录像进程，设备可能不支持 screenrecord")
            }
            Thread.sleep(forTimeInterval: 0.4)
            let alive = try? self.shellText("kill -0 \(pid) 2>/dev/null && echo alive || echo gone")
            guard alive?.contains("alive") == true else {
                try? self.shellText("kill -9 \(pid) 2>/dev/null; rm -f \(remote)")
                throw AdbError.device("screenrecord 启动失败，设备可能不支持录像或没有存储空间")
            }
            return ScreenRecording(pid: pid, remotePath: remote, startedAt: Date())
        }, completion: completion)
    }

    /// Stop a recording gracefully, wait for the MP4 to be finalized, then
    /// pull it into the app's Documents directory (visible in Files).
    func stopScreenRecording(_ recording: ScreenRecording, completion: @escaping (Result<URL, Error>) -> Void) {
        perform({
            // 无论拉取或写入是否失败，都尽力删掉设备端临时文件。
            defer { try? self.shellText("rm -f \(recording.remotePath)") }
            _ = try? self.shellText("kill -INT \(recording.pid)")
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                let state = try? self.shellText("kill -0 \(recording.pid) 2>/dev/null && echo alive || echo gone")
                if state?.contains("gone") == true { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            let data = try self.pullFileSync(recording.remotePath)
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

    func listPackages(system: Bool, completion: @escaping (Result<[AppInfo], Error>) -> Void) {
        perform({
            let flag = system ? "-s" : "-3"
            let text = try self.shellText("pm list packages \(flag)")
            return text.split(whereSeparator: { $0.isNewline }).compactMap { line in
                let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.hasPrefix("package:") else { return nil }
                return AppInfo(packageName: String(value.dropFirst("package:".count)))
            }
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
        perform({ try self.listFilesSync(path) }, completion: completion)
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

    private func pushFileSync(from url: URL, to remotePath: String) throws {
        let stream = try openService("sync:")
        defer { closeStream(stream) }
        let channel = SyncChannel(device: self, stream: stream)
        let mode: UInt32 = 0o100644
        let fileInfo = "\(remotePath),\(mode)"
        try channel.send(id: "SEND", data: Data(fileInfo.utf8))

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let chunk = try handle.read(upToCount: 60 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try channel.send(id: "DATA", data: chunk)
        }
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
            let directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let name = (remotePath as NSString).lastPathComponent
            let destination = directory.appendingPathComponent(name.isEmpty ? "downloaded.file" : name)
            try data.write(to: destination, options: .atomic)
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
        perform({
            let name = "adbhelper-\(UUID().uuidString).apk"
            let remote = "/data/local/tmp/\(name)"
            try self.pushFileSync(from: url, to: remote)
            let output = try self.shellText("pm install -r \(remote)", timeout: 120)
            _ = try? self.shellText("rm -f \(remote)")
            if output.localizedCaseInsensitiveContains("success") { return output }
            throw AdbError.device(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }, completion: completion)
    }
}
