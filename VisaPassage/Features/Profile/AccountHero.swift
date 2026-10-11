import PhotosUI
import SwiftUI

/// The Account tab's profile card, the first row of the settings `List`: a
/// travel-photo banner with the avatar sitting on its lower edge, then who you
/// are (or an invitation to sign in).
struct AccountHero: View {
    @Environment(AuthStore.self) private var auth

    /// Called when the signed-out hero's button is tapped.
    let onSignIn: () -> Void
    let onEditName: () -> Void

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPicker = false
    @State private var busy = false
    @State private var failed = false

    private let bannerHeight: CGFloat = 132
    private let avatarSize: CGFloat = 92
    /// The card's own fill, so the avatar ring cuts cleanly into the banner.
    private let cardFill = Color(.secondarySystemGroupedBackground)

    var body: some View {
        VStack(spacing: 0) {
            banner
            VStack(spacing: Spacing.md) {
                if auth.phase == .loading || auth.isLoadingProfile {
                    placeholder
                } else if auth.isSignedIn {
                    signedIn
                } else {
                    signedOut
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, -avatarSize / 2)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: auth.isLoadingProfile)
        .animation(.easeOut(duration: 0.25), value: auth.phase)
        .photosPicker(isPresented: $showPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await upload(item) }
        }
        .alert("We couldn't update your photo. Please try again.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Banner

    /// A strip of the portrait photo framed on the plane and the cloud line
    /// (about 27–54% down the image).
    private var banner: some View {
        GeometryReader { geo in
            let height = geo.size.width * 1232 / 928
            Image("welcome-plane-above-clouds")
                .resizable()
                .frame(width: geo.size.width, height: height)
                .offset(y: -height * 0.27)
        }
        .frame(height: bannerHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: Loading

    /// One calm placeholder while the session and profile resolve, instead of
    /// the header redrawing as each piece arrives.
    @ViewBuilder
    private var placeholder: some View {
        avatarRing(
            ZStack {
                Circle().fill(Theme.surface2)
                ProgressView()
            }
            .frame(width: avatarSize, height: avatarSize)
        )
        VStack(spacing: Spacing.sm) {
            Text(verbatim: "Firstname Lastname").typography(.h3)
            Text(verbatim: "name@example.com").typeRole(.monoSm)
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading your account"))
    }

    // MARK: Signed in

    @ViewBuilder
    private var signedIn: some View {
        Menu {
            Button { showPicker = true } label: {
                Label(auth.profile?.avatarPath == nil ? "Choose photo" : "Change photo",
                      systemImage: "photo.on.rectangle")
            }
            if auth.profile?.avatarPath != nil {
                Button(role: .destructive) {
                    Task {
                        busy = true
                        if !(await auth.removeAvatar()) { failed = true }
                        busy = false
                    }
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            }
        } label: {
            avatarRing(AvatarView(url: auth.avatarURL, initials: auth.initials, size: avatarSize))
                .overlay(alignment: .bottomTrailing) { cameraBadge }
        }
        .disabled(busy)
        .accessibilityLabel(Text("Profile photo"))
        .accessibilityHint(Text("Change or remove your photo"))

        VStack(spacing: Spacing.xs) {
            Button(action: onEditName) {
                HStack(spacing: 6) {
                    Text(verbatim: auth.displayName)
                        .typography(.h3)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit name"))

            if let email = auth.userEmail, email != auth.displayName {
                Text(verbatim: email)
                    .typeRole(.monoSm)
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }

        if !auth.providers.isEmpty {
            HStack(spacing: Spacing.sm) {
                ForEach(auth.providers, id: \.self) { ProviderChip(provider: $0) }
            }
            .padding(.top, 2)
        }
    }

    private var cameraBadge: some View {
        ZStack {
            Circle().fill(Theme.ink)
            if busy {
                ProgressView().controlSize(.mini).tint(Theme.inkInverse)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkInverse)
            }
        }
        .frame(width: 30, height: 30)
        .overlay(Circle().strokeBorder(cardFill, lineWidth: 3))
        .offset(x: -2, y: -2)
    }

    // MARK: Signed out

    @ViewBuilder
    private var signedOut: some View {
        avatarRing(
            ZStack {
                Circle().fill(Theme.bg)
                Image("brand-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: avatarSize * 0.46)
            }
            .frame(width: avatarSize, height: avatarSize)
        )
        .accessibilityHidden(true)

        VStack(spacing: Spacing.sm) {
            Text("Your VisaPassage account")
                .typography(.h3)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Sign in to track your visas and keep your passports in sync with the website.")
                .typography(.sm)
                .foregroundStyle(Theme.textBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }

        PrimaryButton(title: "Sign in", action: onSignIn)
            .frame(maxWidth: 320)
            .padding(.top, Spacing.xs)
    }

    // MARK: Helpers

    private func avatarRing(_ content: some View) -> some View {
        content
            .overlay(Circle().strokeBorder(cardFill, lineWidth: 4))
            .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let processed = AvatarImageProcessor.jpeg(from: data),
              await auth.updateAvatar(jpeg: processed.jpeg, preview: processed.image) else {
            failed = true
            return
        }
    }
}

/// A sign-in method chip, after the web settings hero: Email in soft blue,
/// third parties neutral with their own mark.
private struct ProviderChip: View {
    let provider: String

    var body: some View {
        HStack(spacing: 5) {
            icon
            Text(verbatim: title).typography(.xs)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .foregroundStyle(isEmail ? StatusHue.blue.softFg : Theme.ink)
        .background(isEmail ? StatusHue.blue.softBg : Theme.bg, in: Capsule())
        .overlay(Capsule().strokeBorder(isEmail ? .clear : Theme.border, lineWidth: Hairline.width))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Signed in with \(title)"))
    }

    private var isEmail: Bool { provider == "email" }

    private var title: String {
        switch provider {
        case "email": "Email"
        case "apple": "Apple"
        case "google": "Google"
        default: provider.capitalized
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch provider {
        case "email": Image(systemName: "envelope.fill").font(.system(size: 11))
        case "apple": Image(systemName: "apple.logo").font(.system(size: 12))
        case "google": Image("google-logo").resizable().scaledToFit().frame(width: 12, height: 12)
        default: Image(systemName: "key.fill").font(.system(size: 11))
        }
    }
}
