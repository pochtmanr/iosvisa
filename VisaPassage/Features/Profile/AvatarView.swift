import SwiftUI
import UIKit

/// A round account avatar: the photo when it loads, else initials on a soft
/// disc. While a photo is on its way it shows a quiet spinner rather than
/// flashing the initials. Used by the Account hero.
struct AvatarView: View {
    let url: URL?
    let initials: String
    var size: CGFloat = 96

    @State private var image: UIImage?
    @State private var loading = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.surface2)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if loading {
                ProgressView()
            } else if !initials.isEmpty {
                Text(verbatim: initials)
                    .font(.system(size: size * 0.36, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = AvatarImageCache.shared.cached(url) { image = hit; return }
            loading = true
            let loaded = await AvatarImageCache.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                loading = false
            }
        }
    }
}

/// In-memory cache for avatar photos, shared by the hero and the tab bar so a
/// photo is fetched once per launch.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private var images: [URL: UIImage] = [:]
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    /// Cached, or fetched once (concurrent callers share the request) and
    /// decoded off the main thread.
    func image(for url: URL) async -> UIImage? {
        if let hit = images[url] { return hit }
        if let task = inFlight[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { images[url] = image }
        return image
    }

    /// Synchronous cache read, so a view can draw a known photo on its first frame.
    func cached(_ url: URL) -> UIImage? { images[url] }

    /// Seed the cache with a photo the user just picked, so it shows at once.
    func store(_ image: UIImage, for url: URL) { images[url] = image }

    /// A 26pt round tab-bar image with a hairline ring. Rendered `.original`
    /// so the tab bar doesn't tint the photo.
    static func tabImage(photo: UIImage?, initials: String) -> UIImage {
        let side: CGFloat = 26
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let image = UIGraphicsImageRenderer(size: rect.size).image { ctx in
            let circle = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            circle.addClip()
            if let photo {
                let scale = max(side / photo.size.width, side / photo.size.height)
                let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                photo.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                      width: size.width, height: size.height))
            } else {
                UIColor.systemGray4.setFill()
                ctx.fill(rect)
                let text = initials.isEmpty ? "?" : initials
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor.label,
                ]
                let size = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attrs)
            }
            UIColor.separator.setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

/// Turns a picked photo into an upload-ready JPEG: square-cropped to the
/// centre, at most 512px, and under the bucket's 2 MB limit.
enum AvatarImageProcessor {
    static let maxBytes = 2 * 1024 * 1024

    static func jpeg(from data: Data) -> (jpeg: Data, image: UIImage)? {
        guard let source = UIImage(data: data) else { return nil }
        let side = min(source.size.width, source.size.height)
        let target = min(512, side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / side
            let w = source.size.width * scale, h = source.size.height * scale
            source.draw(in: CGRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h))
        }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = square.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return (jpeg, square)
            }
        }
        return nil
    }
}
