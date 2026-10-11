#if DEBUG
import SwiftUI

// MARK: - Cards & surfaces

struct LabSurfacesPage: View {
    private static let surfaces: [(String, Color)] = [
        ("surfacePage", Theme.surfacePage),
        ("surfaceRaised", Theme.surfaceRaised),
        ("surfaceSunken", Theme.surfaceSunken),
    ]

    var body: some View {
        LabNote("Paper surfaces separated by a hairline, never by a shadow at rest.")

        LabSpecimen(title: "Card · default", caption: "padding Spacing.xl \(labNumber(Spacing.xl)) · radius Radius.card \(labNumber(Radius.card)) · border Hairline \(labNumber(Hairline.width))") {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Eyebrow(verbatim: "Entry")
                    Text(verbatim: "United Kingdom").typography(.title).foregroundStyle(Theme.ink)
                    Text(verbatim: "ETA · may be eligible").typography(.sm).foregroundStyle(Theme.textBody)
                }
            }
        }

        LabSpecimen(title: "Card · list (padding 0)") {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    CatalogRow(title: "Passport", subtitle: "Valid for the whole stay", trailing: "1") {
                        CatalogGlyph(icon: .passport)
                    }
                    RowDivider()
                    CatalogRow(title: "Proof of funds", subtitle: "Bank statements, last 3 months") {
                        CatalogGlyph(icon: .coin)
                    }
                    RowDivider()
                    CatalogRow(title: "Return ticket", showsChevron: false) {
                        CatalogGlyph(icon: .calendar, tinted: false)
                    }
                }
            }
        }

        LabSpecimen(title: "Surface ramp") {
            HStack(spacing: Spacing.sm) {
                ForEach(Self.surfaces, id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(color)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
                            )
                            .frame(height: 64)
                        Text(verbatim: name).typography(.xs).foregroundStyle(Theme.textBody)
                    }
                }
            }
        }

        LabSpecimen(title: "Input surface · .inputStyle()", caption: "fill surfaceRaised · radius Radius.md \(labNumber(Radius.md)) · padding Spacing.lg \(labNumber(Spacing.lg))") {
            Text(verbatim: "jane@example.com").typography(.body).foregroundStyle(Theme.ink).inputStyle()
        }

        LabSpecimen(title: "Permanently dark band · footerBg") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: "Check before you fly").typography(.title).foregroundStyle(.white)
                UnverifiedChip(onDark: true)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.footerBg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

// MARK: - Badges & labels

struct LabBadgesPage: View {
    var body: some View {
        LabSpecimen(title: "StatusBadge · VisaStatus", caption: "Text and hue come from VisaStatus.label / .hue.") {
            FlowLayout(spacing: Spacing.sm) {
                ForEach(VisaStatus.allCases, id: \.self) { status in
                    StatusBadge(text: status.label, hue: status.hue)
                }
            }
        }

        LabSpecimen(title: "StatusBadge · with icon") {
            FlowLayout(spacing: Spacing.sm) {
                StatusBadge(text: "Visa-free", hue: .green, icon: "checkmark")
                StatusBadge(text: "Processing", hue: .orange, icon: "clock")
                StatusBadge(text: "Refused", hue: .red, icon: "xmark")
                StatusBadge(text: "Premium", hue: .purple, icon: "sparkles")
            }
        }

        LabSpecimen(title: "StatusDot") {
            HStack(spacing: Spacing.md) {
                ForEach(StatusHue.allCases, id: \.self) { StatusDot(hue: $0) }
            }
        }

        LabSpecimen(title: "Chips") {
            FlowLayout(spacing: Spacing.sm) {
                UnverifiedChip()
                TagChip(text: "Schengen", icon: .zone)
                TagChip(text: "90 days", icon: .calendar)
                TagChip(text: "No icon")
            }
        }

        LabSpecimen(title: "Eyebrow + heading") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Eyebrow(verbatim: "Passport strength")
                Text(verbatim: "Where can you go?").typography(.h2).foregroundStyle(Theme.ink)
            }
        }

        LabSpecimen(title: "SectionHeading") {
            SectionHeading(eyebrow: "Before you go", title: "Documents.", muted: "What the border officer may ask for.")
        }

        LabSpecimen(title: "AdvisoryDisclaimer") {
            AdvisoryDisclaimer()
        }

        LabSpecimen(title: "CountryFlag", caption: "sizes 64 · 44 · 32 · 20 (default) · unknown code falls back to xx") {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: "gb", size: 64)
                CountryFlag(iso2: "jp", size: 44)
                CountryFlag(iso2: "de", size: 32)
                CountryFlag(iso2: "br")
                CountryFlag(iso2: "zz")
            }
        }

        LabSpecimen(title: "MapKeyCard · travel") {
            MapKeyCard(mode: .travel(counts: [.visaFree: 62, .visaOnArrival: 31, .evisa: 40, .eta: 4, .visaRequired: 52, .unknown: 6],
                                     active: .all, onToggle: { _ in }))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
}

// MARK: - Catalog blocks

struct LabCatalogPage: View {
    private static let facts: [FactItem] = [
        FactItem(id: "stay", icon: .calendar, label: "Stay", value: "90 days", hint: "in any 180"),
        FactItem(id: "cost", icon: .coin, label: "Cost", value: "£16", hint: nil),
        FactItem(id: "time", icon: .hourglass, label: "Processing", value: "3 days", hint: "usually faster"),
        FactItem(id: "issuer", icon: .building, label: "Issuer", value: "UK Home Office", hint: nil),
        FactItem(id: "valid", icon: .shieldClock, label: "Valid", value: nil, hint: "Not published"),
    ]

    var body: some View {
        LabNote("Blocks shared by the corridor, visa product, checklist, guide and destination screens.")

        LabSpecimen(title: "FactGrid", caption: "Two columns divided by exact 1 pt lines inside a \(labNumber(Radius.card)) pt card. An odd count pads with paper.") {
            FactGrid(items: Self.facts)
        }

        LabSpecimen(title: "CatalogStateCard · loading") {
            CatalogStateCard(kind: .loading)
        }

        LabSpecimen(title: "CatalogStateCard · failed") {
            CatalogStateCard(kind: .failed, retry: {})
        }

        LabSpecimen(title: "StatusChip (welcome art)") {
            StatusChip(
                label: labKey("Your route"),
                route: labKey("GB → JP"),
                rows: [
                    .init(label: labKey("British passport"), status: labKey("Visa-free · 90 days"), tone: .hue(.green), flag: "gb"),
                    .init(label: labKey("Indian passport"), status: labKey("eVisa"), tone: .hue(.blue), flag: "in"),
                    .init(label: labKey("Residence permit"), status: labKey("Not counted"), tone: .neutral),
                ]
            )
        }
    }
}

// MARK: - Purpose cards

/// The landing's and the dashboard's main element: the purpose cards
/// (`PurposeCards.tsx`), with the glyphs and the route ramps they lead to.
struct LabPurposeCardsPage: View {
    @State private var chosen: Purpose? = .study

    var body: some View {
        LabNote("The landing hero (step 1) and the web dashboard share these seven cards. Home opens Explore with the tapped purpose; the welcome's purpose step uses them as a radio group. Press and hold a card to see the pressed state: surface tone, 1 pt ink ring, the others at 50%.")

        LabSpecimen(title: "PurposeCardGrid · Home", caption: "2 columns · 1 pt gaps on Theme.border · \(labNumber(Radius.card)) pt outer radius · travel spans both with the inset photo (\(labNumber(Radius.lg)) pt)") {
            PurposeCardGrid(suggested: .study) { _ in }
        }

        LabSpecimen(title: "PurposeCardGrid · chosen (welcome step)", caption: "Chosen card: Theme.ink fill, short line at 70%. Tap to move the choice.") {
            PurposeCardGrid(selection: chosen) { chosen = $0 }
        }

        LabSpecimen(title: "PurposeIcon · RoutePalette.accent", caption: "24-unit grid, 1.5 stroke, round caps — ported path for path from purposeIcons.tsx") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Purpose.allCases) { p in
                    HStack(spacing: Spacing.md) {
                        PurposeIcon(purpose: p, size: 32).foregroundStyle(RoutePalette.accent(p))
                        Text(verbatim: p.title).typography(.sm).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(verbatim: p.rawValue).font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                    }
                }
            }
        }

        LabSpecimen(title: "Route ramps · RoutePalette", caption: "Depth 1 · 2 · 3+ visa types, then focus. Light left, dark right.") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Purpose.allCases.filter(\.isRoute)) { p in
                    HStack(spacing: Spacing.sm) {
                        Text(verbatim: p.rawValue).typography(.xs).foregroundStyle(Theme.textBody)
                            .frame(width: 72, alignment: .leading)
                        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                            HStack(spacing: 2) {
                                ForEach(1...3, id: \.self) { n in
                                    Rectangle().fill(RoutePalette.depth(n, p)).frame(height: 24)
                                }
                                Rectangle().fill(RoutePalette.accent(p)).frame(height: 24)
                            }
                            .padding(4)
                            .background(Theme.bg)
                            .environment(\.colorScheme, scheme)
                        }
                    }
                }
                HStack(spacing: Spacing.sm) {
                    Text(verbatim: "empty").typography(.xs).foregroundStyle(Theme.textBody)
                        .frame(width: 72, alignment: .leading)
                    ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                        HStack(spacing: 2) {
                            Rectangle().fill(RoutePalette.empty).frame(height: 24)
                            Rectangle().fill(RoutePalette.emptyStrong).frame(height: 24)
                        }
                        .padding(4)
                        .background(Theme.bg)
                        .environment(\.colorScheme, scheme)
                    }
                }
            }
        }

        LabSpecimen(title: "MapKeyCard · route") {
            MapKeyCard(mode: .route(purpose: .study, buckets: [41, 12, 5], none: 138))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }

        LabDrift("The web hatches \"no route\" land on the map. The iOS map has no hatch pattern yet, so no-route and type-hidden countries share RoutePalette.empty.")
    }
}

// MARK: - Buttons

struct LabButtonsPage: View {
    var body: some View {
        LabNote("Ink-filled primary, hairline secondary, glass for sign-in. Press any of them to feel PressShrinkStyle (0.97, ease-out 0.12 s).")

        LabSpecimen(title: "PrimaryButton", caption: "height 52 · Capsule · Theme.accent on Theme.accentContrast") {
            VStack(spacing: Spacing.md) {
                PrimaryButton(title: labKey("Continue")) {}
                PrimaryButton(title: labKey("Working"), loading: true) {}
                PrimaryButton(title: labKey("Disabled"), enabled: false) {}
                PrimaryButton(title: labKey("No icon"), icon: nil) {}
            }
        }

        LabSpecimen(title: "SecondaryButton") {
            VStack(spacing: Spacing.md) {
                SecondaryButton(title: labKey("Back"), icon: "chevron.left") {}
                SecondaryButton(title: labKey("Share route"), icon: "square.and.arrow.up") {}
            }
        }

        LabSpecimen(title: "ApplyOnlineButton", caption: "The one filled-colour control on guide pages: Palette.blue500.") {
            ApplyOnlineButton {}
        }

        LabSpecimen(title: "AuthProviderButton · glass", caption: "Liquid Glass on iOS 26, frosted material before. Shown over a photo, where glass is meant to sit.") {
            VStack(spacing: Spacing.md) {
                AuthProviderButton(title: labKey("Continue with Apple"), systemImage: "apple.logo") {}
                AuthProviderButton(title: labKey("Continue with email"), systemImage: "envelope") {}
                HStack {
                    Spacer()
                    Button {} label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                    }
                    .glassCircle()
                }
            }
            .padding(Spacing.lg)
            .background {
                Image("welcome-plane-above-clouds")
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

// MARK: - Fields & toggles

struct LabFieldsPage: View {
    @State private var email = "jane@example.com"
    @State private var empty = ""
    @State private var purpose = "tourism"
    @State private var unset = ""
    @State private var notify = true
    @State private var off = false
    @State private var date: Date? = Calendar.current.date(from: DateComponents(year: 1992, month: 3, day: 14))
    @State private var noDate: Date?
    @State private var country = "GB"
    @State private var noCountry = ""

    var body: some View {
        LabNote("Labelled fields share FormField (eyebrow label) and .inputStyle(). All of these are live.")

        LabSpecimen(title: "TextFieldRow") {
            VStack(spacing: Spacing.lg) {
                TextFieldRow(label: "Email", text: $email, keyboard: .emailAddress)
                TextFieldRow(label: "Full name", text: $empty, placeholder: "As on your passport")
            }
        }

        LabSpecimen(title: "OptionMenuRow") {
            VStack(spacing: Spacing.lg) {
                OptionMenuRow(label: "Purpose", selection: $purpose, options: ["tourism", "business", "study", "work"])
                OptionMenuRow(label: "Not set", selection: $unset, options: ["tourism", "business"])
            }
        }

        LabSpecimen(title: "DateField") {
            VStack(spacing: Spacing.lg) {
                DateField(label: "Date of birth", date: $date)
                DateField(label: "Expiry", date: $noDate)
            }
        }

        LabDrift("DateField opens its calendar as a bottom sheet with detents. The house rule is centred pop-ups (.floatingSheet), so this is a candidate for the screen sweep.")

        LabSpecimen(title: "CountryPicker") {
            VStack(spacing: Spacing.lg) {
                CountryPicker(label: "Nationality", iso2: $country)
                CountryPicker(label: "Destination", iso2: $noCountry)
            }
        }

        LabSpecimen(title: "ToggleRow", caption: "tint Theme.accent") {
            VStack(spacing: Spacing.md) {
                ToggleRow(label: "Rule change alerts", isOn: $notify)
                ToggleRow(label: "Weekly digest", isOn: $off)
            }
        }
    }
}

// MARK: - Sheets

struct LabSheetsPage: View {
    @State private var showsSolid = false
    @State private var showsGlass = false

    var body: some View {
        LabNote("Dialogs are centred, floating cards on phones too. No bottom sheets. .floatingSheet is the shared presenter.")

        LabSpecimen(title: "floatingSheet · solid", caption: "Page background with a hairline rim. Tap the backdrop or swipe down to close.") {
            SecondaryButton(title: labKey("Open solid sheet")) { showsSolid = true }
        }

        LabSpecimen(title: "floatingSheet · glass", caption: "Liquid Glass on iOS 26, .regularMaterial before. Used by the sign-in card.") {
            SecondaryButton(title: labKey("Open glass sheet")) { showsGlass = true }
        }
        .floatingSheet(isPresented: $showsSolid) { LabSheetContent() }
        .floatingSheet(isPresented: $showsGlass, surface: .glass) { LabSheetContent() }
    }
}

private struct LabSheetContent: View {
    @Environment(\.dismissFloatingSheet) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(verbatim: "Specimen")
            Text(verbatim: "Add a passport").typography(.h3).foregroundStyle(Theme.ink)
            Text(verbatim: "Citizenships and residence permits in one place. No account needed to start.")
                .typography(.body).foregroundStyle(Theme.textBody)
            PrimaryButton(title: labKey("Done"), icon: nil) { dismiss() }
        }
        .padding(Spacing.xl)
    }
}
#endif
