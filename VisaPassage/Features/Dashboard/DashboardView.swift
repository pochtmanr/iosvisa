import SwiftUI
import Observation

/// The home dashboard: featured active applications, a profile-completeness
/// ring, a documents tile, and an "explore destinations" CTA. Mirrors the web
/// `/app` redesign (featured Active applications + completeness ring; no
/// next-steps / expirations widgets).
struct DashboardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(CountryStore.self) private var catalog
    @Environment(TabRouter.self) private var tabs
    @State private var model = DashboardModel()
    @State private var path = NavigationPath()
    @State private var portal: AccessRepository.Portal?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    if let notice = portalNotice { portalCard(notice) }
                    activeSection
                    completenessCard
                    documentsCard
                    exploreCard
                    SecondaryButton(title: "Sign out", icon: "rectangle.portrait.and.arrow.right") {
                        Task { await auth.signOut() }
                    }
                    AdvisoryDisclaimer()
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: VisaApplication.self) { app in
                ApplicationWorkspaceView(application: app)
            }
            .navigationDestination(for: NewApplicationRequest.self) { request in
                NewApplicationFlow(request: request) { app in path.append(app) }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .task { portal = try? await AccessRepository().currentPortal() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Eyebrow(text: greeting)
            Text("Where to next?").typography(.display).foregroundStyle(Theme.ink)
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if !model.activeApplications.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Eyebrow(text: "Active applications")
                ForEach(model.activeApplications) { app in
                    NavigationLink(value: app) {
                        ApplicationRow(application: app, productName: model.names[app.productID])
                    }
                    .buttonStyle(PressShrinkStyle())
                }
            }
        }
    }

    private var completenessCard: some View {
        Card {
            HStack(spacing: Spacing.lg) {
                CompletenessRing(percent: model.completeness?.percent ?? 0)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Profile completeness").typography(.title).foregroundStyle(Theme.ink)
                    if let c = model.completeness {
                        Text("\(c.completeCount) of \(c.totalCount) sections complete. Finish your profile for faster applications.")
                            .typography(.sm).foregroundStyle(Theme.textBody)
                    } else {
                        Text("Finish your profile for faster applications.")
                            .typography(.sm).foregroundStyle(Theme.textBody)
                    }
                    Button("Complete your profile") { tabs.selection = .profile }
                        .typography(.sm).foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var documentsCard: some View {
        Card {
            HStack(spacing: Spacing.lg) {
                Image(systemName: "folder").font(.system(size: 22)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.documentsCount) document\(model.documentsCount == 1 ? "" : "s")")
                        .typography(.title).foregroundStyle(Theme.ink)
                    Text("In your secure vault").typography(.sm).foregroundStyle(Theme.textBody)
                }
                Spacer()
            }
        }
    }

    private var exploreCard: some View {
        Button { tabs.selection = .discover } label: {
            Card {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "globe").font(.system(size: 22)).foregroundStyle(Theme.inkSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Explore destinations").typography(.title).foregroundStyle(Theme.ink)
                        Text("See where your passport can take you.")
                            .typography(.sm).foregroundStyle(Theme.textBody)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Theme.textSoft)
                }
            }
        }
        .buttonStyle(PressShrinkStyle())
    }

    private func portalCard(_ notice: (title: String, body: String)) -> some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "building.2").font(.system(size: 18)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(notice.title).typography(.title).foregroundStyle(Theme.ink)
                    Text(notice.body).typography(.sm).foregroundStyle(Theme.textBody)
                }
            }
        }
    }

    private var greeting: String {
        let name = auth.profile?.legalFirstName ?? auth.profile?.fullName
        return name.map { "Welcome, \($0)" } ?? "Welcome"
    }

    private var portalNotice: (title: String, body: String)? {
        switch portal {
        case .admin:
            return ("You're a platform admin",
                    "Manage the admin portal on the web — this app is the traveler experience.")
        case .agency:
            return ("You manage an agency",
                    "Work cases in the agency portal on the web. You can still use the traveler app here.")
        case .endUser, .none:
            return nil
        }
    }
}

/// Monochrome progress ring for profile completeness.
struct CompletenessRing: View {
    let percent: Int
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().stroke(Theme.surface2, lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%").typeRole(.monoSm).foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
    }
}

/// Loads the dashboard's applications + completeness snapshot.
@MainActor
@Observable
final class DashboardModel {
    var applications: [VisaApplication] = []
    var names: [UUID: String] = [:]
    var completeness: Completeness?
    var documentsCount = 0
    var loading = false

    private let apps = ApplicationRepository()
    private let profiles = ProfileRepository()

    /// Needs-action + in-progress cases, newest first, capped for the dashboard.
    var activeApplications: [VisaApplication] {
        Array(applications.filter { $0.status.bucket != .complete }.prefix(3))
    }

    func load() async {
        loading = true
        defer { loading = false }

        async let appsP = apps.list()
        async let profileP = profiles.currentProfile()
        async let passportCountP = profiles.passportCount()
        async let countsP = profiles.vaultSectionCounts()
        async let docsP = profiles.documentsCount()

        let loadedApps = (try? await appsP) ?? []
        applications = loadedApps
        let ids = Array(Set(loadedApps.map(\.productID)))
        names = (try? await apps.productNames(ids: ids)) ?? names

        let profile = (try? await profileP) ?? nil
        let passportCount = (try? await passportCountP) ?? 0
        let counts = (try? await countsP) ?? VaultSectionCounts()
        documentsCount = (try? await docsP) ?? 0

        completeness = ProfileCompleteness.compute(CompletenessInput(
            personalComplete: ProfileCompleteness.personalComplete(profile),
            contactComplete: ProfileCompleteness.contactComplete(profile),
            passports: passportCount,
            residencies: counts.residencies,
            education: counts.education,
            employment: counts.employment,
            family: counts.family,
            travel: counts.travel,
            background: counts.background
        ))
    }
}
