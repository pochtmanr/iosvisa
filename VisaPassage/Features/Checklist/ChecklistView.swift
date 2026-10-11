import SwiftUI

/// One visa product's document checklist, read-only. Grouped like the web:
/// required documents first, then the ones that apply only in some cases, each
/// in catalog order. A row with a guide opens "How to get it".
struct ChecklistView: View {
    let context: ProductContext

    @State private var catalog = DocumentCatalog()

    var body: some View {
        let docs = context.product.orderedDocuments
        let required = docs.filter(\.required)
        let optional = docs.filter { !$0.required }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Eyebrow(text: "Document checklist")
                    Text(verbatim: context.product.name)
                        .typography(.h2)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: CorridorText.documentsInChecklist(docs.count))
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                }
                if docs.isEmpty {
                    CatalogStateCard(kind: .empty, message: String(localized: "No document checklist for this visa in our data yet."))
                }
                if !required.isEmpty { group(String(localized: "Required"), required) }
                if !optional.isEmpty { group(String(localized: "If applicable"), optional) }
                AdvisoryDisclaimer(text: "Typical eligibility from our visa data. No approval guarantees — official decisions prevail.")
            }
            .padding(Spacing.xl)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task { await catalog.load(passport: context.passport) }
    }

    private func group(_ title: String, _ docs: [DocumentRequirement]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Eyebrow(verbatim: title)
                Spacer()
                Text(verbatim: "\(docs.count)").font(Typography.font(.monoSm)).foregroundStyle(Theme.textSoft)
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                        if index > 0 { RowDivider(inset: 52) }
                        DocumentRow(document: doc, hasGuide: catalog.guide(for: doc) != nil,
                                    passport: context.passport, showsDescription: true)
                    }
                }
            }
        }
    }
}

/// One checklist line: a check glyph (green when required, muted when it only
/// applies in some cases), the label, and a link to its guide when one exists.
struct DocumentRow: View {
    let document: DocumentRequirement
    let hasGuide: Bool
    let passport: String?
    var showsDescription = false

    var body: some View {
        if hasGuide {
            NavigationLink(value: CatalogRoute.guide(GuideContext(requirement: document, passport: passport))) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            CatalogGlyph(icon: .check, size: 22, tinted: document.required)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: document.label)
                    .typography(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if showsDescription, let description = document.description, !description.isEmpty {
                    Text(verbatim: description)
                        .typography(.sm)
                        .foregroundStyle(Theme.textBody)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Spacing.sm) {
                    Text(document.required ? "Required" : "If applicable")
                        .typography(.xs)
                        .foregroundStyle(Theme.textSoft)
                    if hasGuide {
                        Text(verbatim: "·").typography(.xs).foregroundStyle(Theme.textSoft)
                        Text("How to get it").typography(.xs).foregroundStyle(Theme.ink)
                    }
                }
            }
            Spacer(minLength: 0)
            if hasGuide {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
