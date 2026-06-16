import SwiftUI

/// Circular country flag rendered from the bundled `circle-flags` images
/// (`flag-<iso2>` in the asset catalog). Mirrors the web `CountryFlag` primitive:
/// a hairline-bordered circle, falling back to the neutral `xx` flag for unknown
/// or malformed codes.
struct CountryFlag: View {
    let iso2: String?
    var size: CGFloat = 20

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.border, lineWidth: Hairline.width))
    }

    private var assetName: String {
        let code = iso2?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard code.count == 2, code.allSatisfy({ $0.isLetter }) else { return "flag-xx" }
        return UIImage(named: "flag-\(code)") != nil ? "flag-\(code)" : "flag-xx"
    }
}

#Preview {
    HStack(spacing: Spacing.md) {
        CountryFlag(iso2: "us", size: 44)
        CountryFlag(iso2: "GB", size: 32)
        CountryFlag(iso2: "de")
        CountryFlag(iso2: nil)
    }
    .padding()
    .background(Theme.bg)
}
