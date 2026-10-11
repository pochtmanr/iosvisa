import SwiftUI

/// "How to get this document": the `document_guides` entry for the passport's
/// country (or the generic one), or the requirement's own override. Guide text
/// is English-only for now, as on the web (ROADMAP known gaps).
struct DocumentGuideView: View {
    let context: GuideContext

    @State private var catalog = DocumentCatalog()
    @State private var loaded = false
    @State private var safari: SafariLink?

    var body: some View {
        let guide = catalog.guide(for: context.requirement)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Eyebrow(verbatim: catalog.kindName(context.requirement.kind) ?? String(localized: "Documents"))
                    Text(verbatim: context.requirement.label)
                        .typography(.h2)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = context.requirement.description, !description.isEmpty {
                        Text(verbatim: description).typography(.body).foregroundStyle(Theme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let guide {
                    content(guide)
                } else if loaded {
                    CatalogStateCard(kind: .empty, message: String(localized: "No guide for this document in our data yet."))
                } else {
                    CatalogStateCard(kind: .loading)
                }
            }
            .padding(Spacing.xl)
        }
        .background(Theme.groupedBg)
        .navigationTitle("Document guide")
        .navigationBarTitleDisplayMode(.inline)
        .safariSheet($safari)
        .task {
            await catalog.load(passport: context.passport)
            loaded = true
        }
    }

    @ViewBuilder
    private func content(_ guide: DocumentGuide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Eyebrow(text: "How to get this document")
            Text(verbatim: guide.howToObtain)
                .typography(.bodyLg)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if AppLocale.current != .en {
                Text("This guide is available in English only for now.")
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
            }
        }

        let rows: [(CatalogIcon, String, String?)] = [
            (.building, String(localized: "Issued by"), guide.issuingAuthority),
            (.coin, String(localized: "Typical cost"), guide.typicalCost),
            (.hourglass, String(localized: "Typical time"), guide.typicalTime),
        ]
        let shown = rows.filter { !($0.2 ?? "").isEmpty }
        if !shown.isEmpty {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
                        if index > 0 { RowDivider(inset: 0) }
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                CatalogGlyph(icon: row.0, size: 18)
                                Text(verbatim: row.1).typeRole(.eyebrow).textCase(.uppercase).foregroundStyle(Theme.textSoft)
                            }
                            // "…fee (DS-11); expedite +$60" reads one part per line.
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Self.parts(row.2 ?? ""), id: \.self) { part in
                                    Text(verbatim: part).typography(.sm).foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.leading, 26)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.lg)
                    }
                }
            }
        }

        if let link = guide.link {
            SecondaryButton(title: "Official page", icon: "arrow.up.right") { safari = SafariLink(url: link) }
        }

        if let source = guide.source {
            HStack(spacing: Spacing.sm) {
                if let date = CorridorText.verifiedDate(source.verifiedAt) {
                    Text("Verified \(date)").typography(.xs).foregroundStyle(Theme.textSoft)
                }
                if let host = source.url.flatMap(URL.webLink)?.displayHost {
                    Text(verbatim: "· \(host)").font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
                }
                Spacer()
                if let confidence = CorridorText.confidence(source.confidence) {
                    StatusBadge(text: confidence.label, hue: confidence.hue)
                }
            }
        }
    }

    static func parts(_ value: String) -> [String] {
        value.components(separatedBy: "; ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
