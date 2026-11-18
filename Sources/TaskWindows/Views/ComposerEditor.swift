import AppKit
import SwiftUI

enum ComposerReturnAction: Equatable {
    case system, send, newline, ignore

    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                        composing: Bool, repeating: Bool) -> Self {
        guard (keyCode == 36 || keyCode == 76), !composing else { return .system }
        let relevant = modifiers.intersection([.command, .control, .option, .shift])
        if relevant == .shift { return .newline }
        guard relevant.isEmpty || relevant == .command else { return .system }
        return repeating ? .ignore : .send
    }
}

struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    let submit: () -> Void

    private static let font = NSFont.systemFont(ofSize: 14)
    private static let insets = NSSize(width: 10, height: 9)

    func makeNSView(context: Context) -> NSScrollView {
        let editor = Editor(frame: .zero)
        editor.font = Self.font
        editor.textColor = .textColor
        editor.insertionPointColor = .controlAccentColor
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.textContainerInset = Self.insets
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = .width
        editor.setAccessibilityLabel("会话消息")
        editor.delegate = context.coordinator
        editor.string = text

        let scroll = NSScrollView(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        context.coordinator.binding = $text
        editor.submit = submit
        if editor.string != text, !editor.hasMarkedText() {
            let caret = min(editor.selectedRange().location, (text as NSString).length)
            editor.string = text
            editor.setSelectedRange(NSRange(location: caret, length: 0))
            editor.needsDisplay = true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let measured = ((text + " ") as NSString).boundingRect(
            with: NSSize(width: max(1, width - 2 * Self.insets.width), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.font]
        )
        let windowHeight = nsView.window?.contentLayoutRect.height ?? 530
        let limit = max(60, min(126, (windowHeight - 115) * 0.27))
        return CGSize(width: width, height: max(60, min(limit, ceil(measured.height) + 2 * Self.insets.height)))
    }

    static var isComposing: Bool {
        (NSApp.keyWindow?.firstResponder as? Editor)?.hasMarkedText() == true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>

        init(binding: Binding<String>) { self.binding = binding }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            binding.wrappedValue = editor.string
            editor.needsDisplay = true
        }
    }

    private final class Editor: NSTextView {
        var submit: (() -> Void)?

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty {
                ("给这条会话发消息…" as NSString).draw(at: textContainerOrigin, withAttributes: [
                    .font: ComposerEditor.font, .foregroundColor: NSColor.placeholderTextColor
                ])
            }
        }

        override func keyDown(with event: NSEvent) {
            switch action(for: event) {
            case .system: super.keyDown(with: event)
            case .send: submit?()
            case .newline: insertNewline(nil)
            case .ignore: break
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self, event.modifierFlags.contains(.command) {
                switch action(for: event) {
                case .send: submit?(); return true
                case .ignore: return true
                default: break
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        private func action(for event: NSEvent) -> ComposerReturnAction {
            .resolve(keyCode: event.keyCode, modifiers: event.modifierFlags,
                     composing: hasMarkedText(), repeating: event.isARepeat)
        }
    }
}
