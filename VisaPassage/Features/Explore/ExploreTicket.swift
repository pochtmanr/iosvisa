import SwiftUI

// MARK: - Route ticket

/// The picked destination, under the map, as a boarding pass: a strip in the
/// answer's colour (the visa status, or the purpose for routes) carrying the
/// verdict and the stay, then the trip itself — your passport, the route the
/// map just drew, the destination — and the way on. Replaces a header row of
/// flag, name, badge and a close button.
struct RouteTicket<Footer: View>: View {
    /// Your passport's country; nil hides the route (the destination is home).
    let origin: String?
    let destination: String
    /// The strip: verdict, its glyph, and what sits on the right (the stay).
    let verdict: String
    let detail: String?
    let tint: Color
    let tintBg: Color
    @ViewBuilder let glyph: () -> AnyView
    let onClose: () -> Void
    @ViewBuilder let footer: () -> Footer

    @Environment(CountryStore.self) private var catalog

    var body: some View {
        VStack(spacing: 0) {
            strip
            Perforation()
                .padding(.horizontal, Spacing.md)
            VStack(alignment: .leading, spacing: Spacing.md) {
                trip
                footer()
            }
            .padding(Spacing.md)
        }
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .transition(.asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var strip: some View {
        HStack(spacing: Spacing.sm) {
            glyph()
            Text(verdict)
                .typeRole(.eyebrow)
                .textCase(.uppercase)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            if let detail {
                Text(detail)
                    .font(Typography.font(.monoSm))
                    .lineLimit(1)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .foregroundStyle(tint)
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.sm)
        .frame(height: 44)
        .background(tintBg)
    }

    @ViewBuilder
    private var trip: some View {
        let destName = catalog.name(forISO2: destination) ?? destination
        if let origin {
            HStack(alignment: .center, spacing: Spacing.sm) {
                end(origin, name: catalog.name(forISO2: origin) ?? origin, alignment: .leading, strong: false)
                FlightLine()
                end(destination, name: destName, alignment: .trailing, strong: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: Spacing.md) {
                CountryFlag(iso2: destination, size: 36)
                Text(destName).typography(.title).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
        }
    }

    private func end(_ iso2: String, name: String, alignment: HorizontalAlignment, strong: Bool) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            CountryFlag(iso2: iso2, size: strong ? 36 : 28)
            Text(name)
                .typography(strong ? .title : .sm)
                .foregroundStyle(strong ? Theme.ink : Theme.textBody)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// Dashed path with a plane at its middle: the map's arc, as a ticket mark.
private struct FlightLine: View {
    var body: some View {
        ZStack {
            Line()
                .stroke(Theme.border, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))
                .frame(height: 1)
            Image(systemName: "airplane")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 6)
                .background(Theme.bg)
        }
        .frame(width: 64)
        .padding(.bottom, 24)
        .accessibilityHidden(true)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// The tear line under the strip.
private struct Perforation: View {
    var body: some View {
        Line()
            .stroke(Theme.border, style: StrokeStyle(lineWidth: Hairline.width, dash: [3, 3]))
            .frame(height: Hairline.width)
            .accessibilityHidden(true)
    }
}

// MARK: - Purpose picker

/// The purpose control in the map's toolbar: a pill that opens an anchored
/// dropdown (a popover, never a sheet) listing every purpose with its line
/// icon on a soft tile in its hue, a one-line description and a check.
struct PurposeMenu: View {
    @Binding var selection: Purpose
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: Spacing.sm) {
                PurposeIcon(purpose: selection, size: 18)
                    .foregroundStyle(RoutePalette.accent(selection))
                Text(selection.title)
                    .typography(.sm)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(.snappy(duration: 0.2), value: open)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Purpose of your trip"))
        .accessibilityValue(Text(selection.title))
        .accessibilityIdentifier("explore.purpose")
        .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            PurposeDropdown(selection: selection) { picked in
                open = false
                withAnimation(.snappy(duration: 0.25)) { selection = picked }
            }
            .presentationCompactAdaptation(.popover)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct PurposeDropdown: View {
    let selection: Purpose
    let onPick: (Purpose) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Purpose of your trip")
                .typeRole(.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSoft)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)
            ForEach(Purpose.allCases) { p in
                Button { onPick(p) } label: { row(p) }
                    .buttonStyle(PurposeRowStyle())
                    .accessibilityIdentifier("purpose.option.\(p.rawValue)")
                    .accessibilityAddTraits(p == selection ? .isSelected : [])
            }
        }
        .padding(.bottom, Spacing.sm)
        .frame(width: 304)
        .background(Theme.bg)
    }

    private func row(_ p: Purpose) -> some View {
        let accent = RoutePalette.accent(p)
        let active = p == selection
        return HStack(spacing: Spacing.md) {
            PurposeIcon(purpose: p, size: 18)
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .typography(.sm)
                    .fontWeight(active ? .semibold : .regular)
                    .foregroundStyle(Theme.ink)
                Text(p.short)
                    .typography(.xs)
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct PurposeRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surface2 : .clear)
    }
}
