import SwiftUI
import Observation

/// The Applications tab: the user's cases grouped by status bucket, each a card
/// linking into the workspace. Empty state points at the visa checker. Hosts the
/// navigation stack for the new-application wizard and the workspace.
struct ApplicationsListView: View {
    @Environment(CountryStore.self) private var catalog
    @State private var model = ApplicationsListModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.loading && model.applications.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.applications.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.bg)
            .navigationTitle("Applications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(NewApplicationRequest()) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New application")
                }
            }
            .navigationDestination(for: NewApplicationRequest.self) { request in
                NewApplicationFlow(request: request) { app in path.append(app) }
            }
            .navigationDestination(for: VisaApplication.self) { app in
                ApplicationWorkspaceView(application: app)
            }
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }

    // MARK: Sections

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Eyebrow(text: section.title)
                        ForEach(section.applications) { app in
                            NavigationLink(value: app) {
                                ApplicationRow(application: app, productName: model.productName(for: app))
                            }
                            .buttonStyle(PressShrinkStyle())
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.inkSoft)
            Text("No applications yet").typography(.h3)
            Text("Find a visa you're eligible for, then start an application in a few taps.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center)
            Button("Start a new application") { path.append(NewApplicationRequest()) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One application card: destination flag + name, product, status badge, and
/// last-updated.
struct ApplicationRow: View {
    @Environment(CountryStore.self) private var catalog
    let application: VisaApplication
    let productName: String?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.md) {
                CountryFlag(iso2: application.destinationIso2, size: 28)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(catalog.name(forISO2: application.destinationIso2) ?? application.destinationIso2)
                        .typography(.title).foregroundStyle(Theme.ink)
                    if let productName {
                        Text(productName).typography(.sm).foregroundStyle(Theme.textBody)
                    }
                    if let updated = application.updatedAt {
                        Text("Updated \(RelativeDate.string(updated))")
                            .typography(.xs).foregroundStyle(Theme.textSoft)
                    }
                }
                Spacer(minLength: Spacing.sm)
                StatusBadge(text: application.status.label, hue: application.status.hue)
            }
        }
    }
}

/// Loads and groups the user's applications for the list.
@MainActor
@Observable
final class ApplicationsListModel {
    struct Section: Identifiable {
        let bucket: ApplicationStatus.Bucket
        let title: String
        let applications: [VisaApplication]
        var id: String { title }
    }

    var applications: [VisaApplication] = []
    var names: [UUID: String] = [:]
    var loading = false
    var error: String?

    private let repo = ApplicationRepository()

    /// Sections in display order: Needs action → In progress → Complete.
    var sections: [Section] {
        let order: [(ApplicationStatus.Bucket, String)] = [
            (.needsAction, "Needs action"),
            (.inProgress, "In progress"),
            (.complete, "Complete"),
        ]
        return order.compactMap { bucket, title in
            let group = applications.filter { $0.status.bucket == bucket }
            return group.isEmpty ? nil : Section(bucket: bucket, title: title, applications: group)
        }
    }

    func productName(for app: VisaApplication) -> String? { names[app.productID] }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let apps = try await repo.list()
            applications = apps
            let ids = Array(Set(apps.map(\.productID)))
            names = (try? await repo.productNames(ids: ids)) ?? names
            error = nil
        } catch {
            self.error = "Couldn't load your applications."
        }
    }
}

/// Compact relative-date formatter for list rows ("2 days ago").
enum RelativeDate {
    nonisolated(unsafe) private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func string(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
