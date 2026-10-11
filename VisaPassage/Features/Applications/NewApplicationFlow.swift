import SwiftUI
import Observation

/// Context handed to the new-application wizard from a discovery route — the
/// traveller has already chosen a passport, destination, and product. Used as a
/// navigation value out of the destination detail screen.
struct StartApplicationContext: Hashable, Sendable {
    var passportISO2: String?
    var destinationISO2: String
    var productID: UUID
    var productName: String
    var entryType: EntryType
}

/// The navigation value that opens the new-application wizard. With a `context`
/// it jumps straight to confirm (from discovery); without one it runs the cold
/// destination → passport → product picker (from the applications list).
struct NewApplicationRequest: Hashable, Sendable {
    var context: StartApplicationContext? = nil
}

/// The new-application wizard. Builds a `draft` application and hands the created
/// row back via `onCreated` so the host stack can push the workspace.
struct NewApplicationFlow: View {
    let request: NewApplicationRequest
    var onCreated: (VisaApplication) -> Void

    @Environment(CountryStore.self) private var catalog
    @State private var model = NewApplicationModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Eyebrow(text: "New application")
                Text(headline).typography(.h2).foregroundStyle(Theme.ink)

                switch model.step {
                case .destination: destinationStep
                case .passport: passportStep
                case .product: productStep
                case .confirm: confirmStep
                }

                if let error = model.error {
                    Text(error).typography(.sm).foregroundStyle(StatusHue.red.softFg)
                }

                AdvisoryDisclaimer()
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationTitle("Start application")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start(request: request) }
    }

    private var headline: String {
        switch model.step {
        case .destination: return "Where are you going?"
        case .passport: return "Which passport?"
        case .product: return "Choose a visa type"
        case .confirm: return model.productName ?? "Confirm your application"
        }
    }

    // MARK: Steps

    private var destinationStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                CountryPicker(label: "Destination", iso2: $model.destinationISO2)
                PrimaryButton(title: "Continue", enabled: !model.destinationISO2.isEmpty) {
                    Task { await model.chooseDestination() }
                }
            }
        }
    }

    @ViewBuilder
    private var passportStep: some View {
        if model.passports.isEmpty {
            Card {
                Text("Add a passport in your profile vault to start an application.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
            }
        } else {
            VStack(spacing: Spacing.md) {
                ForEach(model.passports) { passport in
                    let iso = passport.citizenshipISO2 ?? ""
                    Button {
                        Task { await model.choosePassport(iso) }
                    } label: {
                        Card {
                            HStack(spacing: Spacing.md) {
                                CountryFlag(iso2: iso, size: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(catalog.name(forISO2: iso) ?? iso)
                                        .typography(.title).foregroundStyle(Theme.ink)
                                    if let number = passport.passportNumber, !number.isEmpty {
                                        Text(number).typography(.xs).foregroundStyle(Theme.textSoft)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13)).foregroundStyle(Theme.textSoft)
                            }
                        }
                    }
                    .buttonStyle(PressShrinkStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var productStep: some View {
        if model.loadingProducts {
            ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xl)
        } else if model.products.isEmpty {
            Card {
                Text("No applyable visa products are listed for this route yet.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
            }
        } else {
            VStack(spacing: Spacing.md) {
                ForEach(model.products) { resolved in
                    Button {
                        model.chooseProduct(resolved)
                    } label: {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(resolved.product.name).typography(.title).foregroundStyle(Theme.ink)
                                HStack(spacing: Spacing.sm) {
                                    StatusBadge(text: resolved.effectiveEligibility.label,
                                                hue: eligibilityHue(resolved.effectiveEligibility))
                                    if let fee = resolved.feeDisplay {
                                        Text(fee).typography(.xs).foregroundStyle(Theme.textBody)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(PressShrinkStyle())
                }
            }
        }
    }

    private var confirmStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                summaryRow("Destination", catalog.name(forISO2: model.destinationISO2) ?? model.destinationISO2)
                summaryRow("Passport", catalog.name(forISO2: model.passportISO2) ?? (model.passportISO2 ?? "—"))
                if let name = model.productName { summaryRow("Visa type", name) }
                Divider().overlay(Theme.border)
                Text("We'll prefill your details from your profile vault. You can review and edit everything in the next step before paying.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
                PrimaryButton(title: "Create application", loading: model.creating) {
                    Task {
                        if let app = await model.create() { onCreated(app) }
                    }
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Eyebrow(text: label)
            Text(value).typography(.body).foregroundStyle(Theme.ink)
        }
    }

    private func eligibilityHue(_ e: VisaEligibility) -> StatusHue {
        switch e {
        case .eligible: return .green
        case .conditional: return .yellow
        case .notEligible: return .red
        case .unknown: return .purple
        }
    }
}

/// Drives the new-application wizard: data loading, step progression, and the
/// final `create`.
@MainActor
@Observable
final class NewApplicationModel {
    enum Step { case destination, passport, product, confirm }

    var step: Step = .destination
    var destinationISO2 = ""
    var passportISO2: String?
    var productID: UUID?
    var productName: String?

    var passports: [Passport] = []
    var products: [ResolvedVisaProduct] = []
    var loadingProducts = false
    var creating = false
    var error: String?

    private let profiles = ProfileRepository()
    private let visa = VisaRepository()
    private let applications = ApplicationRepository()
    private var started = false

    func start(request: NewApplicationRequest) async {
        guard !started else { return }
        started = true
        if let ctx = request.context {
            destinationISO2 = ctx.destinationISO2.uppercased()
            passportISO2 = ctx.passportISO2?.uppercased()
            productID = ctx.productID
            productName = ctx.productName
            await loadPassports()
            // Resolve the passport from discovery, else fall through to picking.
            if passportISO2 == nil { passportISO2 = passports.first?.citizenshipISO2?.uppercased() }
            step = passportISO2 == nil ? .passport : .confirm
        } else {
            await loadPassports()
            step = .destination
        }
    }

    func chooseDestination() async {
        guard !destinationISO2.isEmpty else { return }
        if passports.isEmpty { await loadPassports() }
        step = .passport
    }

    func choosePassport(_ iso: String) async {
        passportISO2 = iso.uppercased()
        await loadProducts()
        step = .product
    }

    func chooseProduct(_ resolved: ResolvedVisaProduct) {
        productID = resolved.product.id
        productName = resolved.product.name
        step = .confirm
    }

    func create() async -> VisaApplication? {
        guard let productID, let passportISO2, !destinationISO2.isEmpty else {
            error = "Pick a passport and visa type first."
            return nil
        }
        creating = true
        error = nil
        defer { creating = false }
        do {
            let profile = try? await profiles.currentProfile()
            let passport = passports.first { $0.citizenshipISO2?.uppercased() == passportISO2 }
            let details = ApplicantDetailsPrefill.make(from: profile, passport: passport)
            return try await applications.create(
                productId: productID,
                passport: passportISO2,
                destination: destinationISO2,
                applicantDetails: details
            )
        } catch {
            self.error = "Couldn't create the application. Please try again."
            return nil
        }
    }

    private func loadPassports() async {
        passports = (try? await profiles.passports()) ?? []
    }

    private func loadProducts() async {
        guard let passportISO2, !destinationISO2.isEmpty else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        let options = try? await visa.destinationOptions(passport: passportISO2, destination: destinationISO2)
        // Applyable products only: not external-only, and not flatly ineligible.
        products = (options?.products ?? []).filter {
            $0.effectiveApplicationMode != .external && $0.effectiveEligibility != .notEligible
        }
    }
}
