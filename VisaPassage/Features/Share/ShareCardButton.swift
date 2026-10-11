import SwiftUI
import UIKit

/// A share button that renders `card` to an image with `ImageRenderer` and
/// shares it with the page's web URL as the message. The image is rendered
/// when the button appears and again whenever `renderID` changes.
struct ShareCardButton<Card: View>: View {
    let url: URL
    var title: LocalizedStringKey = "Share"
    var renderID: String
    @ViewBuilder let card: () -> Card

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    subject: Text(verbatim: "VisaPassage"),
                    message: Text(verbatim: url.absoluteString),
                    preview: SharePreview(Text(verbatim: url.absoluteString), image: image)
                ) {
                    Label(title, systemImage: "square.and.arrow.up")
                }
            } else {
                // Not rendered yet: share the link alone.
                ShareLink(item: url) {
                    Label(title, systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: renderID) { image = render() }
    }

    @MainActor
    private func render() -> Image? {
        let renderer = ImageRenderer(content: card())
        renderer.scale = ShareCardMetrics.scale
        renderer.proposedSize = ProposedViewSize(ShareCardMetrics.size)
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
