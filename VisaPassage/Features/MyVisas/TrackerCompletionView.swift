import SwiftUI

/// The decision summary (`/app/trackers/[id]/complete`): the completion hero,
/// then "Plan your next trip". Open trackers go back to their detail.
struct TrackerCompletionView: View {
    let trackerID: UUID

    @Environment(TrackerStore.self) private var store
    @Environment(ExploreSelection.self) private var explore
    @Environment(TabRouter.self) private var tabs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if let summary = store.trackers.first(where: { $0.id == trackerID }) {
                    CompletionHero(summary: summary, showArchive: true) { dismiss() }
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Plan your next trip")
                            .font(.custom("Geist-Medium", size: 17))
                            .foregroundStyle(Theme.ink)
                        PurposeCardGrid { purpose in
                            explore.open(purpose: purpose)
                            tabs.selection = .explore
                        }
                    }
                } else if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxxl)
                } else {
                    CatalogStateCard(kind: .failed, retry: { Task { await store.load() } })
                }
            }
            .padding(Spacing.xl)
        }
        .background(Theme.surface)
        .navigationTitle("Decision")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !store.loaded { await store.load() } }
    }
}

/// `CompletionHero`: congratulations with what's left before you go when the
/// visa was granted; a calm record with next steps when it was refused or
/// withdrawn.
struct CompletionHero: View {
    let summary: TrackerSummary
    var showArchive = false
    /// Called after archiving (the screen may close).
    var onArchived: () -> Void = {}

    @Environment(TrackerStore.self) private var store
    @Environment(CountryStore.self) private var catalog
    @Environment(TabRouter.self) private var tabs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var archiving = false
    @State private var error: String?
    @State private var showPassports = false

    var body: some View {
        let t = summary.tracker
        Group {
            if t.status == .approved { approved(t) } else { closed(t) }
        }
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: Hairline.width))
        // Fade up 12pt over 700ms, off under Reduce Motion.
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.7), value: appeared)
        .onAppear { appeared = true }
        .passportsEditor(isPresented: $showPassports)
    }

    private var country: String {
        catalog.name(forISO2: summary.tracker.destinationIso2) ?? summary.tracker.destinationIso2
    }

    private var guideRoute: CatalogRoute {
        let t = summary.tracker
        if let passport = t.passportIso2, passport != t.destinationIso2 {
            return .corridor(from: passport, to: t.destinationIso2)
        }
        return .destination(t.destinationIso2)
    }

    // MARK: Approved

    private func approved(_ t: Tracker) -> some View {
        let progress = summary.progress
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                CheckBadge(animate: appeared && !reduceMotion)
                Text("Congratulations")
                    .font(.custom("Geist-Medium", size: 11))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSoft)
                HStack(alignment: .top, spacing: Spacing.md) {
                    CountryFlag(iso2: t.destinationIso2, size: 32)
                    Text("Your visa for \(country) was granted.")
                        .font(.custom("Geist-Medium", size: 26))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Here's what's left before you go.")
                    .font(.custom("Geist-Regular", size: 15))
                    .foregroundStyle(Theme.inkMuted)
                HStack(spacing: Spacing.md) {
                    stat(String(localized: "Documents completed"), "\(progress.done)/\(progress.total)")
                    stat(String(localized: "Days to a decision"),
                         "\(DashboardState.daysBetween(t.createdAt, t.updatedAt))")
                }
            }
            .padding(Spacing.xl)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DashEyebrow(text: String(localized: "Before you go"))
                Button { showPassports = true } label: {
                    tip(String(localized: "Check your passport's validity"),
                        String(localized: "Many countries ask for three to six months beyond your departure date."))
                }
                .buttonStyle(PressShrinkStyle())
                NavigationLink(value: guideRoute) {
                    tip(String(localized: "Entry rules for \(country)"),
                        String(localized: "What to carry at the border and how long you may stay."))
                }
                .buttonStyle(PressShrinkStyle())
                buttons(primaryGuide: false)
                    .padding(.top, Spacing.sm)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: Hairline.width) }
        }
    }

    // MARK: Refused / withdrawn

    private func closed(_ t: Tracker) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: t.destinationIso2, size: 32)
                Text("Decision recorded")
                    .font(.custom("Geist-Medium", size: 11))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(t.status == .refused
                 ? String(localized: "Your application for \(country) was refused.")
                 : String(localized: "You withdrew your application for \(country)."))
                .font(.custom("Geist-Medium", size: 26))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(t.status == .refused
                 ? String(localized: "Read the refusal letter carefully. It usually says what to fix if you apply again.")
                 : String(localized: "Your checklist stays here if you need it again."))
                .font(.custom("Geist-Regular", size: 15))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            buttons(primaryGuide: true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Parts

    @ViewBuilder
    private func buttons(primaryGuide: Bool) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            if primaryGuide {
                NavigationLink(value: guideRoute) {
                    pill(String(localized: "Review the destination guide"), primary: true)
                }
                .buttonStyle(PressShrinkStyle())
                Button { tabs.selection = .explore } label: {
                    pill(String(localized: "Look at other routes"), primary: false)
                }
                .buttonStyle(PressShrinkStyle())
            }
            NavigationLink(value: TrackerRoute.detail(summary.id)) {
                pill(String(localized: "View checklist"), primary: false)
            }
            .buttonStyle(PressShrinkStyle())
            if showArchive && !summary.tracker.isArchived {
                Button {
                    Task { await archive() }
                } label: {
                    pill(String(localized: "Archive"), primary: false)
                }
                .buttonStyle(PressShrinkStyle())
                .disabled(archiving)
            }
        }
        if let error {
            Text(error).typography(.sm).foregroundStyle(StatusHue.red.softFg)
        }
    }

    private func archive() async {
        archiving = true
        defer { archiving = false }
        do {
            try await store.repo.setArchived(summary.id, true)
            await store.load()
            onArchived()
        } catch {
            self.error = TrackerRepository.Failure.saveFailed.message
        }
    }

    private func pill(_ title: String, primary: Bool) -> some View {
        Text(title)
            .font(.custom("Geist-Medium", size: 14))
            .foregroundStyle(primary ? Theme.inkInverse : Theme.ink)
            .padding(.horizontal, Spacing.lg)
            .frame(height: 44)
            .background(primary ? Theme.ink : Theme.bg, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? .clear : Theme.border, lineWidth: Hairline.width))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(value)
                .font(.custom("GeistMono-Regular", size: 22))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.custom("Geist-Regular", size: 12.5))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: Hairline.width))
    }

    private func tip(_ title: String, _ body: String) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.custom("Geist-Medium", size: 14)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(body).font(.custom("Geist-Regular", size: 12.5)).foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            CardArrow().frame(width: 14, height: 14).foregroundStyle(Theme.inkSoft)
        }
        .padding(Spacing.lg)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: Hairline.width))
    }
}

/// The green-soft circle whose check draws in (600ms after 350ms).
private struct CheckBadge: View {
    let animate: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        Circle()
            .fill(StatusHue.green.softBg)
            .frame(width: 44, height: 44)
            .overlay {
                CheckShape()
                    .trim(from: 0, to: drawn)
                    .stroke(StatusHue.green.softFg, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
            }
            .onAppear {
                if animate {
                    withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.6).delay(0.35)) { drawn = 1 }
                } else {
                    drawn = 1
                }
            }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 5 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 10 * s, y: 17 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 7 * s))
            return p
        }
    }
}
