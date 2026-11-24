import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject var model: DeviceViewModel
    @State private var path = "/sdcard"
    @State private var files: [RemoteFile] = []
    @State private var selected: RemoteFile?
    @State private var showImporter = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    TextField("设备路径", text: $path)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(load)
                    Button("前往", action: load)
                }
                .padding(.horizontal)

                List(files) { file in
                    Button {
                        if file.isDirectory {
                            path = file.path
                            load()
                        } else {
                            selected = file
                        }
                    } label: {
                        HStack {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(file.isDirectory ? .orange : .secondary)
                            VStack(alignment: .leading) {
                                Text(file.name).font(.footnote)
                                if !file.isDirectory {
                                    Text("\(file.size) 字节").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if isLoading { ProgressView() }
                    else if files.isEmpty { Text("点击「前往」读取目录").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("文件")
            .toolbar {
                Button("上传") { showImporter = true }
            }
            .confirmationDialog(
                Text(selected?.name ?? ""),
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                )
            ) {
                Button("下载到文件 App") { download() }
                Button("删除", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else {
                        model.notify("无法读取所选文件")
                        return
                    }
                    let name = url.lastPathComponent
                    let destination = path.hasSuffix("/") ? path + name : path + "/" + name
                    model.device.pushFile(from: url, to: destination) { uploadResult in
                        url.stopAccessingSecurityScopedResource()
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
                case .failure(let error):
                    model.notify(error.localizedDescription)
                }
            }
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
