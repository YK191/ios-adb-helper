import Foundation
import Darwin
import Security

// MARK: - Errors

enum AdbError: LocalizedError {
    case connection(String)
    case protocolError(String)
    case authentication(String)
    case timeout(String)
    case io(String)
    case device(String)

    var errorDescription: String? {
        switch self {
        case .connection(let s): return "连接错误：\(s)"
        case .protocolError(let s): return "协议错误：\(s)"
        case .authentication(let s): return "认证失败：\(s)"
        case .timeout(let s): return "超时：\(s)"
        case .io(let s): return "读写失败：\(s)"
        case .device(let s): return "设备返回：\(s)"
        }
    }
}

// MARK: - Wire helpers

/// ADB commands are four ASCII bytes packed into a little-endian UInt32.
enum AdbCommand {
    static let cnxn: UInt32 = code("CNXN")
    static let auth: UInt32 = code("AUTH")
    static let open: UInt32 = code("OPEN")
    static let okay: UInt32 = code("OKAY")
    static let clse: UInt32 = code("CLSE")
    static let wrte: UInt32 = code("WRTE")
    static let fail: UInt32 = code("FAIL")

    static let authToken: UInt32 = 1
    static let authSignature: UInt32 = 2
    static let authPublicKey: UInt32 = 3

    static let version: UInt32 = 0x0100_0000
    static let maxPayload: UInt32 = 1024 * 1024

    private static func code(_ text: String) -> UInt32 {
        var value: UInt32 = 0
        for (index, byte) in text.utf8.enumerated() {
            value |= UInt32(byte) << UInt32(index * 8)
        }
        return value
    }
}

func adbName(_ command: UInt32) -> String {
    var bytes = [UInt8]()
    for shift in stride(from: 0, to: 32, by: 8) {
        bytes.append(UInt8((command >> UInt32(shift)) & 0xff))
    }
    return String(decoding: bytes, as: UTF8.self)
}

func adbAppendLE(_ value: UInt32, to data: inout Data) {
    var v = value.littleEndian
    withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
}

func adbReadLE(_ data: Data, at offset: Int) -> UInt32 {
    var v: UInt32 = 0
    withUnsafeMutableBytes(of: &v) { dst in
        data.dropFirst(offset).prefix(4).withUnsafeBytes { src in
            dst.copyBytes(from: src)
        }
    }
    return UInt32(littleEndian: v)
}

struct AdbPacket {
    let command: UInt32
    let arg0: UInt32
    let arg1: UInt32
    let payload: Data
}

// MARK: - Socket transport

/// Thin synchronous TCP transport. All calls must happen on the device's serial queue.
final class AdbSocket {
    private(set) var fd: Int32 = -1
    private var buffer = Data()

    var isOpen: Bool { fd >= 0 }

    func connect(host: String, port: UInt16) throws {
        close()
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw AdbError.connection(lastError()) }
        fd = socketFD

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        setReadTimeout(15)
        setWriteTimeout(15)

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        let resolved = host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard resolved == 1 else {
            close()
            throw AdbError.connection("请输入有效的 IP 地址")
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            close()
            throw AdbError.connection("无法连接 \(host):\(port) — \(lastError())")
        }
    }

    func setReadTimeout(_ seconds: Double) {
        var value = timeval()
        value.tv_sec = Int(seconds)
        value.tv_usec = Int32((seconds - Double(Int(seconds))) * 1_000_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    func setWriteTimeout(_ seconds: Double) {
        var value = timeval()
        value.tv_sec = Int(seconds)
        value.tv_usec = Int32((seconds - Double(Int(seconds))) * 1_000_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    func sendPacket(command: UInt32, arg0: UInt32, arg1: UInt32 = 0, payload: Data = Data()) throws {
        var packet = Data()
        adbAppendLE(command, to: &packet)
        adbAppendLE(arg0, to: &packet)
        adbAppendLE(arg1, to: &packet)
        adbAppendLE(UInt32(payload.count), to: &packet)
        var checksum: UInt32 = 0
        for byte in payload { checksum = checksum &+ UInt32(byte) }
        adbAppendLE(checksum, to: &packet)
        adbAppendLE(command ^ 0xffff_ffff, to: &packet)
        packet.append(payload)
        try writeAll(packet)
    }

    func readPacket() throws -> AdbPacket {
        while true {
            if buffer.count >= 24 {
                let length = Int(adbReadLE(buffer, at: 12))
                if length > Int(AdbCommand.maxPayload) { throw AdbError.protocolError("数据包过大") }
                if buffer.count >= 24 + length {
                    let command = adbReadLE(buffer, at: 0)
                    let magic = adbReadLE(buffer, at: 20)
                    let packet = AdbPacket(
                        command: command,
                        arg0: adbReadLE(buffer, at: 4),
                        arg1: adbReadLE(buffer, at: 8),
                        payload: Data(buffer.dropFirst(24).prefix(length))
                    )
                    buffer.removeSubrange(0..<(24 + length))
                    guard magic == (command ^ 0xffff_ffff) else {
                        throw AdbError.protocolError("收到损坏的数据包")
                    }
                    return packet
                }
            }
            let chunk = try readSome(max: 64 * 1024)
            if chunk.isEmpty { continue } // interrupted system call
            buffer.append(chunk)
        }
    }

    /// Pushes back a packet so a later reader can consume it.
    func pushBack(_ packet: AdbPacket) {
        var data = Data()
        adbAppendLE(packet.command, to: &data)
        adbAppendLE(packet.arg0, to: &data)
        adbAppendLE(packet.arg1, to: &data)
        adbAppendLE(UInt32(packet.payload.count), to: &data)
        var checksum: UInt32 = 0
        for byte in packet.payload { checksum = checksum &+ UInt32(byte) }
        adbAppendLE(checksum, to: &data)
        adbAppendLE(packet.command ^ 0xffff_ffff, to: &data)
        data.append(packet.payload)
        buffer.insert(contentsOf: data, at: 0)
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
        buffer.removeAll(keepingCapacity: false)
    }

    private func writeAll(_ data: Data) throws {
        var sent = 0
        while sent < data.count {
            let written = data.dropFirst(sent).withUnsafeBytes { raw in
                Darwin.write(fd, raw.baseAddress, raw.count)
            }
            if written > 0 {
                sent += written
            } else if written == 0 {
                throw AdbError.connection("连接已关闭")
            } else if errno == EINTR {
                continue
            } else {
                throw AdbError.io(lastError())
            }
        }
    }

    private func readSome(max count: Int) throws -> Data {
        var storage = [UInt8](repeating: 0, count: count)
        let readCount = storage.withUnsafeMutableBytes { raw in
            Darwin.read(fd, raw.baseAddress, raw.count)
        }
        if readCount > 0 { return Data(storage[0..<readCount]) }
        if readCount == 0 { throw AdbError.connection("连接已关闭") }
        if errno == EINTR { return Data() }
        if errno == EAGAIN || errno == EWOULDBLOCK { throw AdbError.timeout("等待设备响应超时") }
        throw AdbError.io(lastError())
    }

    private func lastError() -> String {
        String(cString: strerror(errno))
    }
}

// MARK: - Authentication

enum AdbAuth {
    /// Signs the 20-byte AUTH token with the embedded 2048-bit RSA key.
    /// adbd expects PKCS#1 v1.5 padding over a SHA-1 DigestInfo, which is exactly
    /// what rsaSignatureDigestPKCS1v15SHA1 produces from a precomputed digest.
    static func sign(_ token: Data) throws -> Data {
        guard let keyData = Data(base64Encoded: AdbKeyData.privateKeyBase64) else {
            throw AdbError.authentication("内置密钥格式错误")
        }
        let attributes = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ] as CFDictionary
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes, &error) else {
            throw AdbError.authentication("无法加载密钥：\(errorMessage(error))")
        }
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureDigestPKCS1v15SHA1, token as CFData, &error) else {
            throw AdbError.authentication("签名失败：\(errorMessage(error))")
        }
        return signature as Data
    }

    static var publicKey: Data {
        Data(base64Encoded: AdbKeyData.publicKeyBase64) ?? Data()
    }

    private static func errorMessage(_ error: Unmanaged<CFError>?) -> String {
        guard let error = error else { return "未知错误" }
        let cfError = error.takeRetainedValue()
        return String(describing: cfError)
    }
}
