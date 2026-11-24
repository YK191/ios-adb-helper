import SwiftUI

/// Read-only UITextView that keeps syntax colors and allows selecting any
/// range of text by long-pressing and dragging the selection handles.
/// SwiftUI's `.textSelection` on separate Text views cannot select across
/// lines/segments, so a single UITextView with attributed text is used.
struct TerminalTextView: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.alwaysBounceVertical = true
        view.indicatorStyle = .white
        view.setContentOffset(.zero, animated: false)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = attributed
    }
}
