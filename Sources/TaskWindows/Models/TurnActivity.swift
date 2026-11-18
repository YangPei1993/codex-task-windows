import Foundation

struct TurnActivity: Identifiable, Equatable {
    enum Kind: String {
        case summary = "reasoning"
        case plan
        case command = "commandExecution"
        case files = "fileChange"
        case tool = "mcpToolCall"
        case dynamicTool = "dynamicToolCall"
        case search = "webSearch"

        var label: String {
            switch self {
            case .summary: "思考摘要"
            case .plan: "计划"
            case .command: "终端命令"
            case .files: "文件变更"
            case .tool, .dynamicTool: "工具调用"
            case .search: "网页搜索"
            }
        }

        var icon: String {
            switch self {
            case .summary: "lightbulb"
            case .plan: "list.bullet.clipboard"
            case .command: "terminal"
            case .files: "doc.badge.gearshape"
            case .tool, .dynamicTool: "wrench.and.screwdriver"
            case .search: "magnifyingglass"
            }
        }
    }

    enum State: String {
        case inProgress, completed, failed, declined

        var label: String {
            switch self {
            case .inProgress: "进行中"
            case .completed: "已完成"
            case .failed: "失败"
            case .declined: "已拒绝"
            }
        }
    }

    let id: String
    let kind: Kind
    let date: Date
    let state: State?
    let text: String?
}
