import Foundation

/// Reads build-time configuration injected into Info.plist from the xcconfig
/// files. The Supabase host (not full URL) is stored to dodge xcconfig's `//`
/// comment handling, so we rebuild the `https://` URL here.
enum AppConfig {
    static let supabaseURL: URL = {
        let host = infoString("SupabaseHost")
        guard let url = URL(string: "https://\(host)") else {
            fatalError("Invalid SupabaseHost in Info.plist: \(host)")
        }
        return url
    }()

    static let supabaseAnonKey: String = infoString("SupabaseAnonKey")

    /// Google iOS OAuth client ID. Optional — empty until provisioned, which is
    /// why this never fatals (the Google sign-in button hides when it's empty).
    static let googleIOSClientID: String = optionalInfoString("GoogleIOSClientID") ?? ""

    /// Whether native Google sign-in can be offered.
    static var hasGoogleSignIn: Bool { !googleIOSClientID.isEmpty }

    /// Custom URL scheme + universal-link host for deep links.
    static let urlScheme = "visapassage"
    static let universalLinkHost = "visapassage.com"

    /// Base URL of the Next.js web app, used for the few server-only API routes
    /// (the anonymous `/api/*` JSON routes).
    static let webBaseURL = URL(string: "https://\(universalLinkHost)")!

    /// The App Store app id (digits), set once the app is listed. The
    /// "Rate VisaPassage" row stays hidden until then.
    static let appStoreID: String? = nil

    /// The App Store "write a review" page, when the app id is known.
    static var appStoreReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    private static func infoString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            fatalError("Missing Info.plist key: \(key). Did you copy Secrets.xcconfig?")
        }
        return value
    }

    /// Like `infoString` but returns nil instead of crashing when the key is
    /// missing or empty — for optional, not-yet-provisioned values.
    private static func optionalInfoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
