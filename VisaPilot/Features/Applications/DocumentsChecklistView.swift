import SwiftUI

/// The Documents step: the product's required/optional document checklist with a
/// ready/total progress bar and an acknowledgment gate. Real file attachment is
/// M4 — here the user confirms they hold the documents to pass the M3 gate.
struct DocumentsChecklistView: View {
    @Bindable var model: ApplicationWorkspaceModel
    var onContinue: () -> Void

    @State private var acknowledged = false
    @State private var loadedAck = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Eyebrow(text: "Documents")
            Text("What you'll need").typography(.h3).foregroundStyle(Theme.ink)

            progress

            if model.checklist.isEmpty {
                Card {
                    Text("No specific documents are listed for this visa type. You can still proceed.")
                        .typography(.sm).foregroundStyle(Theme.textBody)
                }
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(model.checklist) { item in
                        DocumentRow(item: item)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ToggleRow(label: "I have these documents ready", isOn: $acknowledged)
                    Text("You'll upload the files in a later step. Confirming here lets you continue toward payment.")
                        .typography(.xs).foregroundStyle(Theme.textSoft)
                }
            }
            .onChange(of: acknowledged) { _, newValue in
                Task { await model.setDocumentsAcknowledged(newValue) }
            }

            PrimaryButton(title: "Continue", enabled: acknowledged, action: onContinue)
        }
        .onAppear {
            if !loadedAck { acknowledged = model.application.details.documentsAcknowledged; loadedAck = true }
        }
    }

    private var progress: some View {
        let done = model.readiness.docsDone
        let total = max(model.readiness.docsTotal, 1)
        let fraction = Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(done) of \(model.readiness.docsTotal) documents ready")
                .typography(.sm).foregroundStyle(Theme.textBody)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2).frame(height: 6)
                    Capsule().fill(StatusHue.green.solid)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
            if model.readiness.requiredDocsTotal > 0 {
                Text("\(model.readiness.requiredDocsTotal) required")
                    .typography(.xs).foregroundStyle(Theme.textSoft)
            }
        }
    }
}

/// One checklist line: label, required/optional + status badges, optional
/// how-to-obtain guidance.
private struct DocumentRow: View {
    let item: ChecklistItem

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    Text(item.requirement.label).typography(.title).foregroundStyle(Theme.ink)
                    Spacer(minLength: Spacing.sm)
                    StatusBadge(text: item.status.label, hue: item.status.hue)
                }
                HStack(spacing: Spacing.sm) {
                    StatusBadge(text: item.requirement.required ? "Required" : "Optional",
                                hue: item.requirement.required ? .yellow : .blue)
                }
                if let description = item.requirement.description, !description.isEmpty {
                    Text(description).typography(.sm).foregroundStyle(Theme.textBody)
                }
                if let how = item.requirement.howToObtain, !how.isEmpty {
                    Text(how).typography(.xs).foregroundStyle(Theme.textSoft)
                }
            }
        }
    }
}
