import Foundation
import SwiftUI

struct Session: Identifiable {
    let id: String
    let title: String
    let project: String
    let updated: Date
    let activity: Date?
    let started: Date?
    let status: SessionStatus
    let lastAction: String?
    let acceptsMessages: Bool

    var sortDate: Date { max(updated, activity ?? updated, started ?? updated) }

    var deepLink: URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }
}

enum SessionStatus {
    case running, completed, failed, interrupted, uncertain, unknown

    init(_ rawValue: String, activity: Date?, now: Date) {
        switch rawValue {
        case "inProgress":
            self = activity.map { now.timeIntervalSince($0) <= 300 } == true ? .running : .uncertain
        case "completed": self = .completed
        case "failed": self = .failed
        case "interrupted": self = .interrupted
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .running: "进行中"
        case .completed: "已完成"
        case .failed: "失败"
        case .interrupted: "已中断"
        case .uncertain: "待确认"
        case .unknown: "暂无状态"
        }
    }

    var tint: Color {
        switch self {
        case .running: .mint
        case .completed: .green
        case .failed: .red
        case .interrupted, .uncertain: .orange
        case .unknown: .secondary
        }
    }
}

struct SessionMessage: Identifiable, Equatable {
    enum Kind: String {
        case userMessage, progress, result

        var label: String {
            switch self {
            case .userMessage: "你的消息"
            case .progress: "进度"
            case .result: "Codex 回复"
            }
        }
    }

    let id: String
    let turnID: String
    let kind: Kind
    let date: Date
    let text: String
}
