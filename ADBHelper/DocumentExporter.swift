import SwiftUI
import UniformTypeIdentifiers

/// UIKit wrapper around the system "Save to Files" (export) picker.
///
/// The import side uses `DocumentPicker`. For downloads we need the mirror
/// flow: hand the app-sandbox file to `forExporting`, let the user pick the
/// destination in the Files app, and only then call it saved.
struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
