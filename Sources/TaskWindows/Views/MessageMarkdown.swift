import AppKit
import SwiftUI

struct MessageMarkdown: View, Equatable {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(MarkdownDocument(source).sections) { section in
                switch section {
                case .block(let block): blockView(block)
                case .table(_, let table): tableView(table)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.isFileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return .handled
            }
            return .systemAction
        })
    }

    private func blockView(_ block: MarkdownDocument.Block) -> some View {
        let lists = block.ancestors.compactMap { component -> Bool? in
            switch component.kind {
            case .orderedList: true
            case .unorderedList: false
            default: nil
            }
        }
        let ordinal = block.ancestors.compactMap { component -> Int? in
            if case .listItem(let ordinal) = component.kind { return ordinal }
            return nil
        }.first
        let quoted = block.ancestors.contains { $0.kind == .blockQuote }
        return HStack(alignment: .top, spacing: 8) {
            if quoted {
                Rectangle().fill(.secondary.opacity(0.45)).frame(width: 2)
                    .accessibilityHidden(true)
            }
            if let ordinal, let ordered = lists.first {
                Text(ordered ? "\(ordinal)." : "•").foregroundStyle(.secondary)
            }
            blockContent(block)
        }
        .padding(.leading, CGFloat(min(4, max(0, lists.count - 1))) * 13)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func blockContent(_ block: MarkdownDocument.Block) -> some View {
        switch block.kind {
        case .header(let level):
            Text(block.text)
                .font(.system(size: level <= 2 ? 16.5 : 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        case .codeBlock(let languageHint):
            MarkdownCodeBlock(text: block.text, language: languageHint)
        case .thematicBreak:
            Divider().opacity(0.6)
        default:
            Text(block.text).lineSpacing(3.5)
        }
    }

    private func tableView(_ table: MarkdownDocument.Table) -> some View {
        let columnCount = table.columns.count
        return Group {
            if columnCount <= 3 {
                rows(table, columnCount: columnCount)
            } else {
                ScrollView(.horizontal) {
                    rows(table, columnCount: columnCount)
                        .frame(width: CGFloat(columnCount) * 155)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.23)))
    }

    private func rows(_ table: MarkdownDocument.Table, columnCount: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(table.rows) { row in
                MarkdownTableRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(row.cells[column] ?? AttributedString())
                            .fontWeight(row.header ? .semibold : .regular)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: alignment(table.columns[column].alignment))
                            .overlay(alignment: .trailing) {
                                if column < columnCount - 1 {
                                    Rectangle().fill(.secondary.opacity(0.22)).frame(width: 1)
                                }
                            }
                    }
                }
                .overlay(alignment: .bottom) { Divider() }
                .background(.secondary.opacity(row.header ? 0.13 : 0.04))
            }
        }
    }

    private func alignment(_ source: PresentationIntent.TableColumn.Alignment) -> Alignment {
        switch source {
        case .left: .topLeading
        case .center: .top
        case .right: .topTrailing
        @unknown default: .topLeading
        }
    }
}

private struct MarkdownTableRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(subviews.count) * 155
        let widths = columns(totalWidth: width, count: subviews.count)
        let height = zip(subviews, widths).map { view, column in
            view.sizeThatFits(.init(width: column, height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, width) in zip(subviews, columns(totalWidth: bounds.width, count: subviews.count)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: .init(width: width, height: bounds.height))
            x += width
        }
    }

    private func columns(totalWidth: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        if count == 2 { return [totalWidth * 0.33, totalWidth * 0.67] }
        return Array(repeating: totalWidth / CGFloat(count), count: count)
    }
}

private struct MarkdownCodeBlock: View {
    let text: AttributedString
    let language: String?
    @State private var copied = false

    private var rawCode: String {
        String(text.characters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text((language?.isEmpty == false ? language! : "代码").uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rawCode, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(copied ? "已复制" : "复制代码")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(copied ? .teal : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("复制代码段")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.11))

            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(10)
            }
        }
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}
