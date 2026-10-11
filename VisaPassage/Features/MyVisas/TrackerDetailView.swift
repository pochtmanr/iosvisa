import StoreKit
import SwiftUI

/// One visa's tracker (`/app/trackers/[id]`): header, Preparing → Submitted →
/// Decision control, progress, the submission tools, the document checklist
/// (tick, "not needed", your own items), the timeline, and archive/delete.
/// On Home's grouped ground: every block is a white card without a border.
struct TrackerDetailView: View {
    let trackerID: UUID

    @Environment(TrackerStore.self) private var store
    @Environment(CountryStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @State private var detail: TrackerRepository.Detail?
    @State private var failed = false
    @State private var error: String?
    @State private var busy = false
    @State private var askOutcome = false
    @State private var newItem = ""
    @State private var addingItem = false
    @State private var confirmDelete = false
    @State private var showComplete = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let detail {
                    content(detail, proxy: proxy)
                        .padding(Spacing.xl)
                } else if failed {
                    CatalogStateCard(kind: .failed, retry: { Task { await load() } })
                        .padding(Spacing.xl)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxxl)
                }
            }
        }
        .background(Theme.groupedBg)
        .navigationTitle(detail?.tracker.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(isPresented: $showComplete) { TrackerCompletionView(trackerID: trackerID) }
        .confirmationDialog(String(localized: "Delete this visa and its checklist? This can't be undone."),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete"), role: .destructive) { Task { await deleteTracker() } }
        }
    }

    private func load() async {
        do {
            detail = try await store.repo.detail(trackerID)
            failed = false
        } catch {
            failed = true
        }
    }

    /// Run a write, then reload this screen and the shared list.
    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch let failure as TrackerRepository.Failure {
            error = failure.message
        } catch {
            self.error = TrackerRepository.Failure.saveFailed.message
        }
        await load()
        await store.load()
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ d: TrackerRepository.Detail, proxy: ScrollViewProxy) -> some View {
        let t = d.tracker
        let progress = TrackerProgress(d.items)
        let ready = t.status.stage == .preparing && progress.requiredOpen == 0 && progress.total > 0
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header(t)
            statusControl(t)
            progressCard(progress)

            if t.status.stage == .decision {
                Button { showComplete = true } label: {
                    HStack(spacing: Spacing.sm) {
                        Text("See summary")
                        Text(verbatim: "→")
                    }
                    .font(.custom("Geist-Medium", size: 13))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 40)
                    .background(Theme.groupedCard, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                }
                .buttonStyle(PressShrinkStyle())
            }
            if ready { readyBanner }
            if t.isArchived {
                Text("This tracker is archived.").typography(.sm).foregroundStyle(Theme.inkMuted)
            }
            if let error {
                Text(error).typography(.sm).foregroundStyle(StatusHue.red.softFg)
            }

            SubmissionActions(tracker: t, progress: progress, officialURL: d.product?.moreInfoURL,
                              onChecklist: { withAnimation { proxy.scrollTo("checklist", anchor: .top) } },
                              onTimeline: { withAnimation { proxy.scrollTo("timeline", anchor: .top) } })

            checklistSection(d).id("checklist")
            timeline(d.events).id("timeline")
            manage(t)
            Text("VisaPassage doesn't submit applications or review documents. Decisions are made by the issuing authority.")
                .font(.custom("Geist-Regular", size: 12.5))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func header(_ t: Tracker) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            CountryFlag(iso2: t.destinationIso2, size: 40)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(routeLine(t))
                    .font(.custom("Geist-Regular", size: 13))
                    .foregroundStyle(Theme.inkMuted)
                Text(t.title)
                    .font(.custom("Geist-Medium", size: 28))
                    .tracking(-0.56)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func routeLine(_ t: Tracker) -> String {
        let country = catalog.name(forISO2: t.destinationIso2) ?? t.destinationIso2
        if let name = t.travellerName, !name.isEmpty { return "\(country) · \(String(localized: "For \(name)"))" }
        return country
    }

    /// `StatusControl`: the traveller moves their own visa along; Decision asks
    /// what the authority decided. Every move lands on the timeline.
    private func statusControl(_ t: Tracker) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 0) {
                ForEach(TrackerStage.allCases, id: \.self) { stage in
                    let active = stage == t.status.stage
                    Button {
                        pick(stage, tracker: t)
                    } label: {
                        Text(stage == .decision && active ? t.status.label : stage.label)
                            .font(.custom("Geist-Medium", size: 13))
                            .foregroundStyle(active ? Theme.inkInverse : Theme.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, Spacing.md)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(active ? Theme.ink : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.groupedCard, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
            .accessibilityLabel(Text("Application status"))

            if askOutcome {
                FlowLayout(spacing: Spacing.sm) {
                    Text("What was decided?")
                        .font(.custom("Geist-Regular", size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(height: 32)
                    ForEach(TrackerStatus.decisions, id: \.self) { status in
                        Button(status.label) { save(status, tracker: t) }
                            .font(.custom("Geist-Medium", size: 13))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                            .disabled(busy)
                    }
                    Button(String(localized: "Cancel")) { askOutcome = false }
                        .font(.custom("Geist-Medium", size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(height: 32)
                }
            }
        }
    }

    private func pick(_ stage: TrackerStage, tracker t: Tracker) {
        if stage == .decision { askOutcome = true; return }
        guard stage != t.status.stage, let status = stage.status else { return }
        save(status, tracker: t)
    }

    private func save(_ status: TrackerStatus, tracker t: Tracker) {
        askOutcome = false
        Task {
            await run { try await store.repo.setStatus(t.id, from: t.status, to: status) }
            // A decision gets its own screen: congratulations, or a calm record.
            if status.stage == .decision, error == nil {
                if status == .approved, ReviewPrompter().trackerCompleted() { requestReview() }
                showComplete = true
            }
        }
    }

    private func progressCard(_ p: TrackerProgress) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(p.done) of \(p.total) done")
                    .font(.custom("GeistMono-Regular", size: 14))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(p.requiredOpen == 0
                     ? String(localized: "All required documents done")
                     : String(localized: "\(p.requiredOpen) required documents left"))
                    .font(.custom("Geist-Regular", size: 13))
                    .foregroundStyle(Theme.inkMuted)
            }
            TrackerProgressBar(ratio: p.ratio, height: 6)
        }
        .padding(20)
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var readyBanner: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Circle().fill(StatusHue.green.solid).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("All required documents are ready")
                    .font(.custom("Geist-Medium", size: 14)).foregroundStyle(Theme.ink)
                Text("Next, book an appointment or submit your application. Then mark it as submitted.")
                    .font(.custom("Geist-Regular", size: 13)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Checklist

    private func checklistSection(_ d: TrackerRepository.Detail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Documents")
                .font(.custom("Geist-Medium", size: 17))
                .foregroundStyle(Theme.ink)

            // Legacy catalog data: always labelled, always with the source.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Unverified checklist").font(.custom("Geist-Medium", size: 13)).foregroundStyle(Theme.ink)
                Text("This list comes from our catalog and isn't verified against the official source. Confirm every requirement with the embassy or official portal before you submit.")
                    .font(.custom("Geist-Regular", size: 13)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.xl) {
                    if let s = d.product?.moreInfoURL, let url = URL(string: s) {
                        Button { openURL(url) } label: { linkText(String(localized: "Official source") + " ↗") }
                    }
                    NavigationLink(value: guideRoute(d.tracker)) { linkText(String(localized: "Full guide")) }
                }
                .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            if d.newRequirementCount > 0, let productID = d.tracker.productID {
                HStack(alignment: .center, spacing: Spacing.md) {
                    Text("Our catalog now lists \(d.newRequirementCount) requirements this tracker doesn't have.")
                        .font(.custom("Geist-Regular", size: 13)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(String(localized: "Add to checklist")) {
                        Task { await run { _ = try await store.repo.addNewRequirements(trackerID: d.tracker.id, productID: productID, existing: d.items) } }
                    }
                    .font(.custom("Geist-Medium", size: 13))
                    .foregroundStyle(Theme.inkInverse)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 34)
                    .background(Theme.ink, in: Capsule())
                    .disabled(busy)
                }
                .padding(Spacing.lg)
                .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }

            VStack(spacing: 0) {
                ForEach(Array(d.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider(inset: Spacing.lg + 20 + 14) }
                    ChecklistItemRow(item: item, busy: busy) { status in
                        Task { await run { try await store.repo.setItemStatus(item.id, status) } }
                    } onRemove: {
                        Task { await run { try await store.repo.deleteCustomItem(item.id) } }
                    }
                }
            }
            .background(Theme.groupedCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            addItem(d.tracker.id)
        }
    }

    private func linkText(_ s: String) -> some View {
        Text(s)
            .font(.custom("Geist-Medium", size: 13))
            .foregroundStyle(Theme.ink)
            .underline(color: Theme.border)
    }

    private func guideRoute(_ t: Tracker) -> CatalogRoute {
        if let passport = t.passportIso2, passport != t.destinationIso2 {
            return .corridor(from: passport, to: t.destinationIso2)
        }
        return .destination(t.destinationIso2)
    }

    @ViewBuilder
    private func addItem(_ trackerID: UUID) -> some View {
        if addingItem {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("What do you need?").font(.custom("Geist-Medium", size: 13)).foregroundStyle(Theme.ink)
                TextField(String(localized: "For example, translated birth certificate"), text: $newItem)
                    .textFieldStyle(.plain)
                    .font(.custom("Geist-Regular", size: 15))
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 44)
                    .background(Theme.groupedBg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit { submitItem(trackerID) }
                HStack(spacing: Spacing.md) {
                    Button(String(localized: "Add item")) { submitItem(trackerID) }
                        .font(.custom("Geist-Medium", size: 14))
                        .foregroundStyle(Theme.inkInverse)
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: 40)
                        .background(Theme.ink, in: Capsule())
                        .disabled(busy || newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(String(localized: "Cancel")) { addingItem = false; newItem = "" }
                        .font(.custom("Geist-Medium", size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(Spacing.lg)
            .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else {
            Button { addingItem = true } label: {
                Text("+ \(String(localized: "Add your own item"))")
                    .font(.custom("Geist-Medium", size: 14))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 44)
                    .background(Theme.groupedCard, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
            }
            .buttonStyle(PressShrinkStyle())
        }
    }

    private func submitItem(_ trackerID: UUID) {
        let label = newItem
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        newItem = ""
        Task { await run { try await store.repo.addCustomItem(trackerID: trackerID, label: label) } }
    }

    // MARK: Timeline and manage

    @ViewBuilder
    private func timeline(_ events: [TrackerEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Timeline").font(.custom("Geist-Medium", size: 15)).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, e in
                        HStack(alignment: .top, spacing: Spacing.md) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(e.toStatus.hue?.solid ?? Theme.inkSoft)
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                if index < events.count - 1 {
                                    Rectangle().fill(Theme.border).frame(width: Hairline.width)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.fromStatus == nil
                                     ? String(localized: "Tracker started")
                                     : String(localized: "Moved to \(e.toStatus.label)"))
                                    .font(.custom("Geist-Medium", size: 13.5))
                                    .foregroundStyle(Theme.ink)
                                if let date = DashboardState.parseTimestamp(e.createdAt) {
                                    Text(date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
                                        .font(.custom("GeistMono-Regular", size: 11.5))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                if let note = e.note, !note.isEmpty {
                                    Text(note).font(.custom("Geist-Regular", size: 12.5)).foregroundStyle(Theme.inkMuted)
                                }
                            }
                            .padding(.bottom, index < events.count - 1 ? Spacing.lg : 0)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func manage(_ t: Tracker) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Manage").font(.custom("Geist-Medium", size: 15)).foregroundStyle(Theme.ink)
            HStack(spacing: Spacing.lg) {
                Button(t.isArchived ? String(localized: "Restore from archive") : String(localized: "Archive")) {
                    Task { await run { try await store.repo.setArchived(t.id, !t.isArchived) } }
                }
                .font(.custom("Geist-Medium", size: 14))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Spacing.lg)
                .frame(height: 40)
                .background(Theme.groupedCard, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                .disabled(busy)

                Button(String(localized: "Delete")) { confirmDelete = true }
                    .font(.custom("Geist-Medium", size: 13))
                    .foregroundStyle(StatusHue.red.solid)
                    .disabled(busy)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func deleteTracker() async {
        do {
            try await store.repo.delete(trackerID)
            await store.load()
            dismiss()
        } catch {
            self.error = TrackerRepository.Failure.saveFailed.message
        }
    }
}

/// One checklist row (`ChecklistRow`): tick it once you have it; "not needed"
/// drops it from the count; your own items can be removed.
private struct ChecklistItemRow: View {
    let item: TrackerItem
    let busy: Bool
    let onStatus: (TrackerItemStatus) -> Void
    let onRemove: () -> Void

    var body: some View {
        let done = item.status == .done
        let skipped = item.status == .notApplicable
        HStack(alignment: .top, spacing: 14) {
            Button { onStatus(done ? .todo : .done) } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(done ? StatusHue.green.solid : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(done ? StatusHue.green.solid : (skipped ? Theme.border : Theme.ink.opacity(0.3)),
                                          lineWidth: Hairline.width)
                    )
                    .overlay {
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .padding(.top, 2)
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .disabled(busy || skipped)
            .accessibilityLabel(Text(item.label))
            .accessibilityAddTraits(done ? .isSelected : [])

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.label)
                    .font(.custom("Geist-Medium", size: 14))
                    .foregroundStyle(done || skipped ? Theme.inkMuted : Theme.ink)
                    .strikethrough(done || skipped, color: Theme.ink.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
                Text(kindLabel(skipped: skipped))
                    .font(.custom("Geist-Regular", size: 12))
                    .foregroundStyle(Theme.inkSoft)
                if let description = item.description, !description.isEmpty, !skipped {
                    Text(description)
                        .font(.custom("Geist-Regular", size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: Spacing.sm)
            Button(item.isCustom
                   ? String(localized: "Remove item")
                   : (skipped ? String(localized: "I need this") : String(localized: "Not needed"))) {
                if item.isCustom { onRemove() } else { onStatus(skipped ? .todo : .notApplicable) }
            }
            .font(.custom("Geist-Medium", size: 12.5))
            .foregroundStyle(Theme.inkMuted)
            .disabled(busy)
            .padding(.top, 2)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        // "Not needed" rows sink to the page's grey.
        .background(skipped ? Theme.groupedBg : Theme.groupedCard)
    }

    private func kindLabel(skipped: Bool) -> String {
        if skipped { return String(localized: "itemStatus.notApplicable", defaultValue: "Not needed") }
        if item.isCustom { return String(localized: "Added by you") }
        return item.required ? String(localized: "Required") : String(localized: "Optional")
    }
}
