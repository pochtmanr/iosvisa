import SafariServices
import SwiftUI

/// A web page in `SFSafariViewController`, so the website, privacy, terms and
/// "how we verify" open inside the app with Safari's reader and share sheet.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A URL that can drive `.sheet(item:)`.
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
