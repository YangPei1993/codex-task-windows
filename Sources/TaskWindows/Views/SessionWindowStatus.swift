import SwiftUI

struct SessionHeaderDecoration: View {
    static let bandHeight: CGFloat = 3.5

    let status: SessionStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if status == .running && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    let period = 2.8
                    let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                    let strength = 0.5 - 0.5 * cos(2 * .pi * time / period)
                    paint(bandOpacity: 0.36 + 0.64 * strength, glowOpacity: 0.09 + 0.21 * strength)
                }
            } else if status != .unknown {
                paint(bandOpacity: 0.9, glowOpacity: status == .running ? 0.20 : 0.16)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func paint(bandOpacity: Double, glowOpacity: Double) -> some View {
        Canvas { context, size in
            let band = CGRect(origin: .zero, size: CGSize(width: size.width, height: Self.bandHeight))
            context.fill(Path(band), with: .color(status.tint.opacity(bandOpacity)))

            let glow = CGRect(x: 0, y: band.maxY, width: size.width, height: max(0, size.height - band.height))
            context.fill(
                Path(glow),
                with: .linearGradient(
                    Gradient(colors: [status.tint.opacity(glowOpacity), status.tint.opacity(0.03)]),
                    startPoint: CGPoint(x: 0, y: glow.minY), endPoint: CGPoint(x: 0, y: glow.maxY)
                )
            )
        }
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    var animates = false
    var showsDetails: Bool?
    var emphasized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: animates && !reduceMotion && status == .running)
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)

            Text(status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize()
            if let showsDetails {
                Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 9, height: 10)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tint.opacity(emphasized ? 0.28 : 0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(status.tint.opacity(emphasized ? 0.65 : 0.28)))
        .help(status.explanation)
    }
}

struct SessionWindowStatus: View {
    let store: SessionStore
    let original: Session
    let openInCodex: () -> Void
    @State private var showingDetails = false
    @State private var hovering = false

    private var session: Session { store.sessions.first { $0.id == original.id } ?? original }

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            StatusBadge(status: session.status, animates: true, showsDetails: showingDetails,
                        emphasized: hovering || showingDetails)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: 104, height: 24)
        .onHover { hovering = $0 }
        .accessibilityLabel("会话状态：\(session.status.label)")
        .accessibilityHint("显示本轮状态详情")
        .help("查看本轮状态详情")
        .popover(isPresented: $showingDetails) {
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            StatusBadge(status: session.status)
            Text(session.status.explanation)
                .fixedSize(horizontal: false, vertical: true)
            if let activity = session.activity {
                LabeledContent("最近活动") {
                    Text(activity.formatted(.dateTime.hour().minute().second())).monospacedDigit()
                }
                if let action = session.lastAction {
                    Text(action).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.error != nil {
                Label("本地状态同步暂不可用", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if session.status == .failed || session.status == .uncertain {
                Button("在 Codex 查看") {
                    showingDetails = false
                    openInCodex()
                }
                .buttonStyle(.link)
            }
        }
        .font(.subheadline)
        .padding(14)
        .frame(width: 246, alignment: .leading)
    }
}
