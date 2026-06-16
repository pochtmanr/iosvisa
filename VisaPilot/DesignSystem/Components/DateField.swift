import SwiftUI

/// Branded date input: a field row showing the formatted date ("14 Mar 1992")
/// that opens a native graphical calendar in a sheet. Binds an optional `Date`;
/// vault forms convert to/from ISO `"yyyy-MM-dd"` strings via `DateOnly`.
struct DateField: View {
    let label: String
    @Binding var date: Date?
    var placeholder: String = "Select date"
    var fromYear: Int = 1900
    var toYear: Int = Calendar.current.component(.year, from: Date()) + 15

    @State private var showing = false
    @State private var draft = Date()

    var body: some View {
        FormField(label: label) {
            Button {
                draft = date ?? defaultDraft
                showing = true
            } label: {
                HStack {
                    Text(displayText)
                        .typography(.body)
                        .foregroundStyle(date == nil ? Theme.textSoft : Theme.ink)
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSoft)
                }
                .inputStyle()
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showing) { sheet }
    }

    private var displayText: String {
        guard let date else { return placeholder }
        return DateOnly.displayString(from: date)
    }

    /// A reasonable starting point for the calendar when nothing is set.
    private var defaultDraft: Date {
        // Mid-range, biased toward adult DOBs without forcing it.
        Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date()
    }

    private var range: ClosedRange<Date> {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let lower = cal.date(from: DateComponents(year: fromYear, month: 1, day: 1)) ?? .distantPast
        let upper = cal.date(from: DateComponents(year: toYear, month: 12, day: 31)) ?? .distantFuture
        return lower...upper
    }

    private var sheet: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $draft, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .padding(Spacing.lg)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { date = nil; showing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { date = draft; showing = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
