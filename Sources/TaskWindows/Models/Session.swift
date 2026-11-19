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
    let currentTurnID: String?

    var sortDate: Date { max(updated, activity ?? updated, started ?? updated) }

    var deepLink: URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }

    /// C 端人性化相对时间展示（当天显示时分，昨天显示“昨天 HH:mm”，更早显示月日时分）
    static func friendlyTimestamp(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        } else if calendar.isDateInYesterday(date) {
            return "昨天 " + date.formatted(.dateTime.hour().minute())
        } else {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
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
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .interrupted: .gray
        case .uncertain: .orange
        case .unknown: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .running: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .interrupted: "pause.circle.fill"
        case .uncertain: "clock.badge.exclamationmark"
        case .unknown: "minus.circle"
        }
    }

    var explanation: String {
        switch self {
        case .running: "Codex 正在处理本轮请求。"
        case .completed: "Codex 已结束本轮处理。"
        case .failed: "本轮执行失败。可以在 Codex 中查看错误详情。"
        case .interrupted: "本轮执行已中断。"
        case .uncertain: "最近 5 分钟没有新的本地活动。可以在 Codex 中确认当前状态。"
        case .unknown: "本地记录还没有提供本轮状态。"
        }
    }
}

struct SessionMessage: Identifiable, Equatable {
    enum QuestionContext {
        case related, previous
    }

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
    var questionContext: QuestionContext?

    var questionLabel: String {
        switch questionContext {
        case .related: "关联提问"
        case .previous: "最近一次提问"
        case nil: kind.label
        }
    }
}
