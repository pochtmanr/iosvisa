#if DEBUG
import SwiftUI

// MARK: - Pages

/// One page of the gallery, grouped like Doppler's Lab: Foundations, Surfaces,
/// Controls, Screens.
enum DesignLabPage: String, CaseIterable, Identifiable {
    case typeLadder
    case colour
    case geometry
    case glyphs

    case surfaces
    case badges
    case catalog
    case purposeCards

    case buttons
    case fields
    case sheets

    case welcome
    case shareCards
    case fullScreens

    var id: String { rawValue }

    enum PageGroup: String, CaseIterable, Identifiable {
        case foundations = "Foundations"
        case surfaces = "Surfaces"
        case controls = "Controls"
        case screens = "Screens"

        var id: String { rawValue }

        var pages: [DesignLabPage] {
            DesignLabPage.allCases.filter { $0.group == self }
        }
    }

    var group: PageGroup {
        switch self {
        case .typeLadder, .colour, .geometry, .glyphs: .foundations
        case .surfaces, .badges, .catalog, .purposeCards: .surfaces
        case .buttons, .fields, .sheets: .controls
        case .welcome, .shareCards, .fullScreens: .screens
        }
    }

    var title: String {
        switch self {
        case .typeLadder: "Type ladder"
        case .colour: "Colour"
        case .geometry: "Spacing & radii"
        case .glyphs: "Glyphs"
        case .surfaces: "Cards & surfaces"
        case .badges: "Badges & labels"
        case .catalog: "Catalog blocks"
        case .purposeCards: "Purpose cards"
        case .buttons: "Buttons"
        case .fields: "Fields & toggles"
        case .sheets: "Sheets"
        case .welcome: "Welcome art"
        case .shareCards: "Share cards"
        case .fullScreens: "Whole screens"
        }
    }

    var icon: String {
        switch self {
        case .typeLadder: "textformat.size"
        case .colour: "paintpalette"
        case .geometry: "ruler"
        case .glyphs: "star.circle"
        case .surfaces: "square.on.square"
        case .badges: "tag"
        case .catalog: "square.grid.2x2"
        case .purposeCards: "square.grid.3x2"
        case .buttons: "capsule"
        case .fields: "switch.2"
        case .sheets: "rectangle.center.inset.filled"
        case .welcome: "photo"
        case .shareCards: "square.and.arrow.up"
        case .fullScreens: "iphone"
        }
    }
}

// MARK: - Lab controls

/// The Lab's own appearance override. Lab-local: it repaints the page being
/// viewed, never the app behind it.
enum LabAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum LabStorage {
    static let appearance = "designLab.appearance"
    /// Index into `DynamicTypeSize.allCases`; -1 follows the system.
    static let typeSize = "designLab.typeSize"
}

// MARK: - Design Lab

/// The design system, rendered.
///
/// Every specimen is drawn by the **same types the app ships**: `Card`,
/// `PrimaryButton`, `StatusBadge`, `.typography(_:)`, `Theme`, `StatusHue`,
/// `Spacing`, `Radius`. Captions read the values back out of those tokens and
/// never retype them. Change a token in `DesignSystem/` and it changes here
/// and on every screen at once, which is the point: tune the language here,
/// then carry it to the screens.
///
/// Reached from Settings ▸ Developer ▸ Design Lab. `#if DEBUG` only.
struct DesignLabView: View {
    var body: some View {
        List {
            Section {
                Text(verbatim: "Every specimen is drawn by the shipping components and tokens in DesignSystem/. Edit a token there and it moves here and on every screen. Use the slider button on a page to force light or dark and to try Dynamic Type sizes.")
                    .typography(.sm)
                    .foregroundStyle(Theme.textBody)
            }
            ForEach(DesignLabPage.PageGroup.allCases) { group in
                Section {
                    ForEach(group.pages) { page in
                        NavigationLink {
                            DesignLabPageView(page: page)
                        } label: {
                            Label {
                                Text(verbatim: page.title)
                            } icon: {
                                Image(systemName: page.icon)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                } header: {
                    Text(verbatim: group.rawValue)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Design Lab"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One Lab page: the specimens in a scroll view, with the appearance and
/// Dynamic Type overrides applied to the content only.
struct DesignLabPageView: View {
    let page: DesignLabPage

    @AppStorage(LabStorage.appearance) private var appearance: LabAppearance = .system
    @AppStorage(LabStorage.typeSize) private var typeSizeIndex = -1
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                content
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .environment(\.colorScheme, appearance.scheme ?? systemScheme)
        .dynamicTypeSize(typeSize)
        .navigationTitle(Text(verbatim: page.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $appearance) {
                        ForEach(LabAppearance.allCases) { Text(verbatim: $0.title).tag($0) }
                    } label: {
                        Text(verbatim: "Appearance")
                    }
                    Picker(selection: $typeSizeIndex) {
                        Text(verbatim: "System (\(Self.name(of: systemTypeSize)))").tag(-1)
                        ForEach(Array(DynamicTypeSize.allCases.enumerated()), id: \.offset) { index, size in
                            Text(verbatim: Self.name(of: size)).tag(index)
                        }
                    } label: {
                        Text(verbatim: "Text size")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
    }

    private var typeSize: DynamicTypeSize {
        let sizes = DynamicTypeSize.allCases
        return sizes.indices.contains(typeSizeIndex) ? sizes[typeSizeIndex] : systemTypeSize
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .typeLadder: LabTypeLadderPage()
        case .colour: LabColourPage()
        case .geometry: LabGeometryPage()
        case .glyphs: LabGlyphsPage()
        case .surfaces: LabSurfacesPage()
        case .badges: LabBadgesPage()
        case .catalog: LabCatalogPage()
        case .purposeCards: LabPurposeCardsPage()
        case .buttons: LabButtonsPage()
        case .fields: LabFieldsPage()
        case .sheets: LabSheetsPage()
        case .welcome: LabWelcomePage()
        case .shareCards: LabShareCardsPage()
        case .fullScreens: LabFullScreensPage()
        }
    }

    static func name(of size: DynamicTypeSize) -> String {
        switch size {
        case .xSmall: "xSmall"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large (default)"
        case .xLarge: "xLarge"
        case .xxLarge: "xxLarge"
        case .xxxLarge: "xxxLarge"
        case .accessibility1: "AX1"
        case .accessibility2: "AX2"
        case .accessibility3: "AX3"
        case .accessibility4: "AX4"
        case .accessibility5: "AX5"
        @unknown default: "Other"
        }
    }
}

// MARK: - Shared specimen chrome

/// A titled specimen: eyebrow, the live sample, then a mono caption carrying
/// the token values read back out of the design layer.
struct LabSpecimen<Content: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(verbatim: title)
            content
            if let caption {
                Text(verbatim: caption)
                    .font(Typography.font(.monoSm))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A page's opening paragraph.
struct LabNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .typography(.sm)
            .foregroundStyle(Theme.textBody)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A flagged gap between the design layer and the screens: something the Lab
/// can see that the tokens do not cover yet.
struct LabDrift: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(Typography.font(.xs))
            Text(verbatim: text)
                .typography(.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(StatusHue.orange.softFg)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatusHue.orange.softBg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// Passes a Lab string to a component that takes a `LocalizedStringKey`
/// without the literal landing in `Localizable.xcstrings`: the catalog only
/// extracts literals written at a `LocalizedStringKey` call site.
func labKey(_ text: String) -> LocalizedStringKey {
    LocalizedStringKey(text)
}

/// Formats a token value: whole numbers without a decimal, others to two places.
func labNumber(_ value: CGFloat) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
}

#Preview {
    NavigationStack { DesignLabView() }
}
#endif
