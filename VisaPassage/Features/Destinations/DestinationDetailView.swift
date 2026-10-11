import SwiftUI

/// Routes a traveller can take into one destination, resolved against their
/// primary selected passport. Mirrors the web destination detail: a baseline
/// regime chip, then resolved products grouped by purpose, each with eligibility,
/// fees, processing,.
struct DestinationDetailView: View {
    let destinationISO2: String

    @Environment(DiscoverySelection.self) private var selection
    @Environment(CountryStore.self) private var catalog

    @State private var options: DestinationVisaOptions?
    @State private var baseline: VisaRequirement?
    @State private var loading = true
    @State private var failed = false

    private let visa = VisaRepository()

    private var country: Country? { catalog.country(destinationISO2) }
    private var passport: String? { selection.primaryPassport }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                } else if failed {
                    Text("Couldn't load routes for this destination.")
                        .typography(.sm).foregroundStyle(Theme.textBody)
                } else {
                    routeSections
                }
                AdvisoryDisclaimer()
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationTitle(country?.displayName ?? destinationISO2)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: passport) { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CountryFlag(iso2: country?.iso2 ?? destinationISO2, size: 44)
            Text(country?.displayName ?? destinationISO2).typography(.h1)
            if let baseline {
                HStack(spacing: Spacing.sm) {
                    StatusBadge(text: baseline.status.label, hue: baseline.status.hue)
                    if let days = baseline.daysAllowed {
                        Text("Up to \(days) days").typography(.xs).foregroundStyle(Theme.textBody)
                    }
                }
            }
            if let passport, let label = catalog.name(forISO2: passport) {
                Text("For \(label)").typography(.sm).foregroundStyle(Theme.textBody)
            }
        }
    }

    @ViewBuilder
    private var routeSections: some View {
        let groups = groupedRoutes
        if groups.isEmpty {
            Text("No specific visa products are listed yet for this destination. The baseline regime above applies.")
                .typography(.sm).foregroundStyle(Theme.textBody)
        } else {
            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Eyebrow(verbatim: group.category.groupLabel)
                    ForEach(group.products) { resolved in
                        RouteCard(resolved: resolved)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private struct RouteGroup { let category: VisaCategory; let products: [ResolvedVisaProduct] }

    private var groupedRoutes: [RouteGroup] {
        guard let options else { return [] }
        let byCategory = Dictionary(grouping: options.products) { $0.product.category }
        return byCategory
            .map { RouteGroup(category: $0.key, products: $0.value.sorted { $0.product.sortOrder < $1.product.sortOrder }) }
            .sorted { $0.category.sortRank < $1.category.sortRank }
    }

    private func load() async {
        guard let passport else { loading = false; return }
        loading = true
        failed = false
        do {
            async let opts = visa.destinationOptions(passport: passport, destination: destinationISO2)
            async let base = visa.baselineStatus(passport: passport, destination: destinationISO2)
            options = try await opts
            baseline = try await base
        } catch {
            failed = true
        }
        loading = false
    }
}

/// One resolved route. Shows entry type, eligibility, fee and processing.
private struct RouteCard: View {
    let resolved: ResolvedVisaProduct

    private var product: VisaProduct { resolved.product }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(product.name).typography(.title).foregroundStyle(Theme.ink)

                HStack(spacing: Spacing.sm) {
                    StatusBadge(text: entryLabel, hue: .blue)
                    StatusBadge(text: resolved.effectiveEligibility.label, hue: eligibilityHue)
                }

                if let summary = product.summary, !summary.isEmpty {
                    Text(summary).typography(.sm).foregroundStyle(Theme.textBody)
                }

                HStack(spacing: Spacing.lg) {
                    if let fee = resolved.feeDisplay { metric("Fee", fee) }
                    if let proc = resolved.processingDisplay { metric("Processing", proc) }
                    if let stay = product.maxStayDays { metric("Max stay", String(localized: "\(stay) days")) }
                }


            }
        }
    }

    private var entryLabel: String {
        switch product.entryType {
        case .visaFree: return String(localized: "Visa-free")
        case .visaOnArrival: return String(localized: "Visa on arrival")
        case .evisa: return String(localized: "eVisa")
        case .eta: return String(localized: "ETA")
        case .consular: return String(localized: "Consular visa")
        case .unknown: return String(localized: "Visa")
        }
    }

    private var eligibilityHue: StatusHue {
        switch resolved.effectiveEligibility {
        case .eligible: return .green
        case .conditional: return .yellow
        case .notEligible: return .red
        case .unknown: return .purple
        }
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).typeRole(.eyebrow).textCase(.uppercase).foregroundStyle(Theme.textSoft)
            Text(value).typography(.sm).foregroundStyle(Theme.ink)
        }
    }
}
