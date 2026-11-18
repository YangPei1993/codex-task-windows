import Foundation

struct MarkdownDocument {
    struct Block: Identifiable {
        let id: Int
        let kind: PresentationIntent.Kind
        var text: AttributedString
        let ancestors: [PresentationIntent.IntentType]
    }

    struct Table {
        struct Row: Identifiable {
            let id: Int
            let header: Bool
            var cells: [Int: AttributedString] = [:]
        }

        let columns: [PresentationIntent.TableColumn]
        var rows: [Row] = []
    }

    enum Section: Identifiable {
        case block(Block)
        case table(Int, Table)

        var id: Int {
            switch self {
            case .block(let block): block.id
            case .table(let id, _): id
            }
        }
    }

    let sections: [Section]

    init(_ source: String) {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options), !parsed.characters.isEmpty else {
            sections = [.block(Block(id: 0, kind: .paragraph, text: AttributedString(source), ancestors: []))]
            return
        }

        var blocks: [Block] = []
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let intent = components.first
            let id = intent?.identity ?? 0
            var piece = AttributedString(parsed[run.range])
            piece.presentationIntent = nil
            if let url = run.link {
                piece.link = Self.safeLink(url)
            }
            if blocks.last?.id == id {
                blocks[blocks.count - 1].text.append(piece)
            } else {
                blocks.append(Block(id: id, kind: intent?.kind ?? .paragraph, text: piece,
                                    ancestors: Array(components.dropFirst())))
            }
        }
        sections = Self.groupTables(blocks)
    }

    private static func groupTables(_ blocks: [Block]) -> [Section] {
        var sections: [Section] = []
        var active: (id: Int, value: Table)?
        for block in blocks {
            guard case .tableCell(let index) = block.kind,
                  let row = block.ancestors.first,
                  let table = block.ancestors.first(where: {
                      if case .table = $0.kind { return true }
                      return false
                  }),
                  case .table(let columns) = table.kind else {
                if let active { sections.append(.table(active.id, active.value)) }
                active = nil
                sections.append(.block(block))
                continue
            }
            if active?.id != table.identity {
                if let active { sections.append(.table(active.id, active.value)) }
                active = (table.identity, Table(columns: columns))
            }
            if active?.value.rows.last?.id != row.identity {
                active?.value.rows.append(Table.Row(id: row.identity, header: row.kind == .tableHeaderRow))
            }
            if let rowIndex = active?.value.rows.indices.last {
                active?.value.rows[rowIndex].cells[index] = block.text
            }
        }
        if let active { sections.append(.table(active.id, active.value)) }
        return sections
    }

    private static func safeLink(_ url: URL) -> URL? {
        if ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return url }
        if url.isFileURL, (url.host ?? "").isEmpty { return url }
        if url.scheme == nil, url.host == nil, url.path.hasPrefix("/") {
            return URL(fileURLWithPath: url.path)
        }
        return nil
    }
}
