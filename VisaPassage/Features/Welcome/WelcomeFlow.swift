import SwiftUI

/// First-launch welcome: three paged cards that retell the landing's "How it
/// works" (passports → compare → track) over the landing photos. Ends as a
/// guest ("Get started") or in the floating sign-in sheet. Either way it sets
/// `welcome.completed`, so it never shows again.
struct WelcomeFlow: View {
    static let completedKey = "welcome.completed"

    @Environment(AuthStore.self) private var auth
    @AppStorage(WelcomeFlow.completedKey) private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = WelcomeFlow.debugStartPage
    @State private var showSignIn = false
    @State private var folderOpen = false

    private let pageCount = 3
    private let controlsHeight: CGFloat = 150

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                passportsPage.tag(0)
                comparePage.tag(1)
                trackPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                controls
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.sm)
        }
        .floatingSheet(isPresented: $showSignIn) {
            AuthSheet()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { finish() }
        }
        .onChange(of: page) { _, newPage in
            if newPage == 0 { openFolder() }
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "welcome.debugSignIn") { showSignIn = true } }
        #endif
    }

    /// Debug builds can open on a given page (`-welcome.debugPage 2`) for screenshots.
    private static var debugStartPage: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "welcome.debugPage")
        #else
        return 0
        #endif
    }

    // MARK: Pages

    private var passportsPage: some View {
        WelcomePage(
            number: 1,
            photo: "welcome-plane-above-clouds",
            title: "Add every passport you hold.",
            message: "Citizenships and residence permits in one place. No account needed to start.",
            bottomInset: controlsHeight
        ) {
            ZStack {
                LandingStamp(name: "stamp-singapore", width: 96, rotation: 11, delay: 0.5)
                    .offset(x: 112, y: -96)
                LandingStamp(name: "stamp-france", width: 88, rotation: -9, delay: 0.7)
                    .offset(x: -118, y: -58)
                LandingStamp(name: "stamp-canada", width: 84, rotation: -13, delay: 0.9)
                    .offset(x: 104, y: 92)
                PassportFolder(width: 232, open: folderOpen)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                    .offset(y: 24)
            }
            // Below the plane in the photo.
            .offset(y: 56)
            .onAppear(perform: openFolder)
        }
    }

    private var comparePage: some View {
        WelcomePage(
            number: 2,
            photo: "welcome-cliff-village",
            crop: .trailing,
            title: "See every route, side by side.",
            message: "Compare what each of your passports needs for any destination: visa-free days, visa type, fees and processing time.",
            bottomInset: controlsHeight
        ) {
            ZStack {
                LandingStamp(name: "stamp-hawaii", width: 84, rotation: 9, delay: 0.3)
                    .offset(x: 108, y: -104)
                StatusChip(label: "Example", route: "United States · Tourism", rows: [
                    .init(label: "Italian passport", status: "Visa-free · 90 days", tone: .hue(.green), flag: "it"),
                    .init(label: "Russian passport", status: "Visa required", tone: .hue(.red), flag: "ru"),
                ])
                .frame(maxWidth: 340)
                .environment(\.colorScheme, .light)
            }
        }
    }

    private var trackPage: some View {
        WelcomePage(
            number: 3,
            photo: "welcome-terraced-garden",
            title: "Track your application in one place.",
            message: "Get your document checklist, mark each one ready, and log every date from appointment to decision.",
            bottomInset: controlsHeight
        ) {
            ZStack(alignment: .topLeading) {
                ChecklistSketch()
                    .frame(width: 220)
                    .rotationEffect(.degrees(-4))
                    .offset(x: -12, y: -6)
                StatusChip(label: "Tracker", route: "Schengen · Tourism", rows: [
                    .init(label: "Passport copy", status: "Ready", tone: .hue(.green)),
                    .init(label: "Bank statements", status: "In progress", tone: .hue(.yellow)),
                    .init(label: "Appointment", status: "14 Nov", tone: .neutral),
                ])
                .frame(width: 290)
                .offset(x: 40, y: 92)
            }
            .frame(width: 330, height: 260, alignment: .topLeading)
            .environment(\.colorScheme, .light)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Image("brand-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 24)
                .accessibilityHidden(true)
            Text(verbatim: "VisaPassage")
                .typography(.title)
                .foregroundStyle(.white)
            Spacer()
            if page < pageCount - 1 {
                Button("Skip") { finish() }
                    .font(Typography.font(.sm))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(.white.opacity(0.14), in: Capsule())
            }
        }
        .frame(height: 44)
        .padding(.top, Spacing.sm)
    }

    private var controls: some View {
        VStack(spacing: Spacing.lg) {
            PageDots(count: pageCount, current: page)

            let isLast = page == pageCount - 1
            Button {
                if isLast {
                    finish()
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) { page += 1 }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(isLast ? "Get started" : "Continue").typography(.sm)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(.black)
                .background(.white, in: Capsule(style: .continuous))
            }
            .buttonStyle(PressShrinkStyle())

            Button { showSignIn = true } label: {
                Text("I already have an account")
                    .typography(.sm)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(PressShrinkStyle())
        }
        .frame(height: controlsHeight, alignment: .bottom)
    }

    // MARK: Actions

    private func openFolder() {
        folderOpen = false
        if reduceMotion { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.35)) { folderOpen = true }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.3)) { completed = true }
    }
}

/// Capsule page indicator: the current page stretches into a pill.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index == current ? 1 : 0.4))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}

#Preview {
    WelcomeFlow()
        .environment(AuthStore())
}
