import SwiftUI

/// Reusable list + add/edit/delete scaffold shared by every repeating vault
/// section (passports, residencies, family, employment, education, travel). The
/// caller supplies how to load/delete rows, how to render a row, and the edit
/// form (which performs its own insert/update then calls `onDone`).
struct VaultSectionView<Model: Identifiable & Sendable, Row: View, Editor: View>: View {
    let title: String
    let emptyText: String
    let load: () async throws -> [Model]
    let remove: (Model) async throws -> Void
    let row: (Model) -> Row
    let editor: (Model?, @escaping () -> Void) -> Editor

    init(
        title: String,
        emptyText: String,
        load: @escaping () async throws -> [Model],
        delete: @escaping (Model) async throws -> Void,
        @ViewBuilder row: @escaping (Model) -> Row,
        @ViewBuilder editor: @escaping (Model?, @escaping () -> Void) -> Editor
    ) {
        self.title = title
        self.emptyText = emptyText
        self.load = load
        self.remove = delete
        self.row = row
        self.editor = editor
    }

    @State private var items: [Model] = []
    @State private var loading = true
    @State private var failed = false
    @State private var showingNew = false
    @State private var editingItem: Model?
    @State private var pendingDelete: Model?

    var body: some View {
        List {
            if loading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if failed {
                Text("Couldn't load this section. Pull to retry.")
                    .typography(.sm).foregroundStyle(Theme.textBody)
                    .listRowSeparator(.hidden)
            } else if items.isEmpty {
                Text(emptyText)
                    .typography(.sm).foregroundStyle(Theme.textBody)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    Button { editingItem = item } label: {
                        row(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = item } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add")
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(isPresented: $showingNew) {
            editor(nil) { showingNew = false; Task { await reload() } }
        }
        .sheet(item: $editingItem) { item in
            editor(item) { editingItem = nil; Task { await reload() } }
        }
        .confirmationDialog(
            "Delete this entry? This can't be undone.",
            isPresented: deleteDialogBinding,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { Task { await delete(item) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func reload() async {
        do {
            items = try await load()
            failed = false
        } catch {
            failed = true
        }
        loading = false
    }

    private func delete(_ item: Model) async {
        pendingDelete = nil
        try? await remove(item)
        await reload()
    }
}

/// A compact two-line row used by most vault sections.
struct VaultRow: View {
    let title: String
    var subtitle: String?
    var badge: String?

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title.isEmpty ? "Untitled" : title)
                    .typography(.body).foregroundStyle(Theme.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).typography(.sm).foregroundStyle(Theme.textBody)
                }
            }
            Spacer()
            if let badge {
                StatusBadge(text: badge, hue: .blue)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12)).foregroundStyle(Theme.textSoft)
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Standard sheet chrome for a vault edit form: a titled NavigationStack with
/// Cancel + a loading-aware Save button.
struct VaultEditScaffold<Content: View>: View {
    let title: String
    let saveTitle: String
    var saving: Bool = false
    var canSave: Bool = true
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    content
                }
                .padding(Spacing.xl)
            }
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSave) {
                        if saving { ProgressView() } else { Text(saveTitle) }
                    }
                    .disabled(!canSave || saving)
                }
            }
        }
    }
}
