import Foundation

/// Pure onboarding-gate logic, mirroring the web rule: a user is "onboarded"
/// once they've finished the wizard **or** already hold at least one passport
/// (the web backfill stamps pre-wizard passport holders, so they never see it).
enum OnboardingGate {
    static func isOnboarded(onboardingCompletedAt: Date?, passportCount: Int) -> Bool {
        onboardingCompletedAt != nil || passportCount > 0
    }
}
