import SwiftUI

/// The Tracking timeline. Composes a synthesized "started" milestone + the real
/// `application_status_events` rows + honest future placeholders, mirroring the
/// web `StatusTimeline`. Copy never promises approval — the decision rests with
/// the issuing authority.
struct StatusTimelineView: View {
    let status: ApplicationStatus
    let createdAt: Date?
    let events: [ApplicationStatusEvent]
    let assisted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                row(entry, isLast: index == entries.count - 1)
            }
        }
    }

    private struct Entry: Sendable {
        var title: String
        var detail: String?
        var date: Date?
        var state: State
        enum State { case past, current, future }
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        // Synthesized start.
        result.append(Entry(title: "Application started", detail: nil, date: createdAt, state: .past))

        // Real recorded events (server-mediated transitions).
        for event in events {
            result.append(Entry(title: event.toStatus.label, detail: event.note, date: event.createdAt, state: .past))
        }

        // Ready milestone (synthesized when no explicit event recorded it).
        let ready = status == .ready || ApplicationReadiness.postPayment.contains(status)
        if ready && !events.contains(where: { $0.toStatus == .ready }) {
            let isCurrent = status == .ready
            result.append(Entry(title: "Ready to pay", detail: isCurrent ? "Complete checkout to continue." : nil,
                                 date: nil, state: isCurrent ? .current : .past))
        }

        result.append(contentsOf: futureEntries)
        return result
    }

    /// Honest placeholders for what's still ahead, by current status.
    private var futureEntries: [Entry] {
        let prepDetail = assisted
            ? "An expert partner is being assigned."
            : "We prepare your guided submission package."
        let decision = Entry(title: "Decision",
                             detail: "The final decision rests with the issuing authority.",
                             date: nil, state: .future)

        switch status {
        case .draft:
            return [
                Entry(title: "Payment", detail: nil, date: nil, state: .future),
                Entry(title: "Preparation", detail: prepDetail, date: nil, state: .future),
                Entry(title: "Submission", detail: nil, date: nil, state: .future),
                decision,
            ]
        case .ready:
            return [
                Entry(title: "Preparation", detail: prepDetail, date: nil, state: .future),
                Entry(title: "Submission", detail: nil, date: nil, state: .future),
                decision,
            ]
        case .paid, .offered, .claimed, .inProgress, .docsRequested:
            return [
                Entry(title: "Submission", detail: nil, date: nil, state: .future),
                decision,
            ]
        case .submittedToAuthority, .decisionPending:
            return [decision]
        default:
            return []
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: 0) {
                dot(entry.state)
                if !isLast {
                    Rectangle().fill(Theme.border).frame(width: Hairline.width, height: 36)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .typography(.body)
                    .foregroundStyle(entry.state == .future ? Theme.textSoft : Theme.ink)
                if let date = entry.date {
                    Text(DateOnly.displayString(from: date)).typography(.xs).foregroundStyle(Theme.textSoft)
                }
                if let detail = entry.detail {
                    Text(detail).typography(.xs).foregroundStyle(Theme.textBody)
                }
            }
            .padding(.bottom, isLast ? 0 : Spacing.md)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func dot(_ state: Entry.State) -> some View {
        switch state {
        case .past:
            Circle().fill(Theme.ink).frame(width: 10, height: 10)
        case .current:
            Circle().fill(StatusHue.blue.solid).frame(width: 12, height: 12)
        case .future:
            Circle().strokeBorder(Theme.border, lineWidth: Hairline.width).frame(width: 10, height: 10)
        }
    }
}
