import SwiftUI

/// The Profile tab — a sectioned hub linking to every vault area, plus account
/// info and sign-out.
struct ProfileHomeView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        NavigationStack {
            List {
                accountSection
                Section("Identity") {
                    link("Personal", systemImage: "person.text.rectangle") { ProfileDetailsView() }
                    link("Contact", systemImage: "envelope") { ProfileContactView() }
                    link("Passports", systemImage: "book.closed") { PassportsView() }
                }
                Section("History") {
                    link("Residencies", systemImage: "house") { ResidenciesView() }
                    link("Family", systemImage: "person.2") { FamilyView() }
                    link("Employment", systemImage: "briefcase") { EmploymentView() }
                    link("Education", systemImage: "graduationcap") { EducationView() }
                    link("Travel history", systemImage: "airplane") { TravelHistoryView() }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }

    private var accountSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(auth.profile?.displayName ?? "Your profile")
                    .typography(.title).foregroundStyle(Theme.ink)
                if let email = auth.userEmail {
                    Text(email).typeRole(.monoSm).foregroundStyle(Theme.textBody)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func link(_ title: String, systemImage: String,
                      @ViewBuilder destination: () -> some View) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
