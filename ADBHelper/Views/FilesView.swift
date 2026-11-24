import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var path = "/sdcard"
    @State private var files: [RemoteFile] = []
    @State private var selected: RemoteFile?
    @State private var showImporter = false
    @State private var showUploadTip = false
    @State private var isLoading = false

    private let shortcuts = ["/sdcard", "/sdcard/Download", "/sdcard/DCIM", "/"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                pathBar

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shortcuts, id: \.self) { item in
                            Button {
                                path = item
                                load()
                            } label: {
                                Text(item)
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        (path == item ? AppTheme.mint : Color.secondary).opacity(path == item ? 0.18 : 0.10),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(path == item ? AppTheme.mint : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                ZStack {
                    AppTheme.canvas.ignoresSafeArea()
                    if files.isEmpty {
                        EmptyStateView(
                            systemImage: isLoading ? "hourglass" : "folder",
                            title: isLoading ? "正在读取目录…" : "目录为空",
                            message: isLoading ? "正在通过 ADB 列出文件" : "换个路径试试，或上传文件到当前目录"
                        )
                    } else {
                        List(files) { file in
                            Button { open(file) } label: { fileRow(file) }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.card)
                                .listRowSeparatorTint(AppTheme.border)
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("文件管理")
            .navigationBarTitleDisplayMode(.large)
            .tint(AppTheme.mint)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if path != "/" {
                            path = NSString(string: path).deletingLastPathComponent
                            if path.isEmpty { path = "/" }
                            load()
                        }
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                    .disabled(path == "/" || path.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showUploadTip = true } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task { load() }
            .confirmationDialog(
                Text(selected?.name ?? ""),
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                )
            ) {
                Button("下载到文件 App", systemImage: "square.and.arrow.down") { download() }
                Button("删除", systemImage: "trash", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            }
            .alert("上传到设备", isPresented: $showUploadTip) {
                Button("取消", role: .cancel) {}
                Button("选择文件") { showImporter = true }
            } message: {
                Text("会打开系统文件选择器，点一下文件就会自动选中返回，然后上传到当前设备目录（上传时需要连接设备）。如果列表里没有文件，请先在「文件」App 里把文件存到「我的 iPhone」中。")
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker { url in
                    showImporter = false
                    model.notify("已选择 \(url.lastPathComponent)")
                    let didAccess = url.startAccessingSecurityScopedResource()
                    let name = url.lastPathComponent
                    let destination = path.hasSuffix("/") ? path + name : path + "/" + name
                    model.device.pushFile(from: url, to: destination) { uploadResult in
                        if didAccess { url.stopAccessingSecurityScopedResource() }
                        DispatchQueue.main.async {
                            switch uploadResult {
                            case .success(let text):
                                model.notify(text)
                                load()
                            case .failure(let error):
                                model.notify(error.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.mint)
            TextField("设备路径", text: $path)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.footnote, design: .monospaced))
                .textFieldStyle(.plain)
                .onSubmit(load)
            Button {
                load()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((file.isDirectory ? Color.orange : AppTheme.blue).opacity(0.15))
                Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(for: file.name))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(file.isDirectory ? .orange : AppTheme.blue)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text(file.isDirectory ? "目录" : "\(file.size) 字节")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "mp4", "mkv", "avi", "mov": return "film"
        case "mp3", "wav", "m4a", "ogg": return "music.note"
        case "apk": return "app.badge"
        case "txt", "log", "json", "xml": return "doc.text"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    private func open(_ file: RemoteFile) {
        if file.isDirectory {
            path = file.path
            load()
        } else {
            selected = file
        }
    }

    private func load() {
        guard model.ensureConnected() else { return }
        isLoading = true
        model.device.listFiles(path: path) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let list): files = list
                case .failure(let error): model.notify(error.localizedDescription)
                }
            }
        }
    }

    private func download() {
        guard let file = selected else { return }
        selected = nil
        model.device.pullFile(from: file.path) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    model.notify("已保存到文件 App：\(url.lastPathComponent)")
                case .failure(let error):
                    model.notify(error.localizedDescription)
                }
            }
        }
    }

    private func delete() {
        guard let file = selected else { return }
        selected = nil
        model.run("rm -f \"\(file.path)\"", success: "已删除")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { load() }
    }
}
