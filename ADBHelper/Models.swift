import Foundation

struct RemoteFile: Identifiable, Hashable {
    let name: String
    let path: String
    let mode: UInt32
    let size: UInt32
    let mtime: UInt32

    var id: String { path }
    var isDirectory: Bool { (mode & 0xf000) == 0x4000 }
}

struct AppInfo: Identifiable, Hashable {
    let packageName: String
    var id: String { packageName }
}

struct ConnectionRecord: Codable, Identifiable, Hashable {
    let host: String
    let port: Int
    var id: String { "\(host):\(port)" }
}

struct ScreenRecording: Identifiable {
    let id = UUID()
    let pid: Int
    let remotePath: String
    let startedAt: Date
}

struct QuickCommand: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var command: String

    init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}
