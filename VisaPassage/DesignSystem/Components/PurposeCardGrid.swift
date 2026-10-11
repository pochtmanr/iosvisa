import SwiftUI

/// The purpose cards, shared by Home (the web dashboard's `PurposeWidget`) and
/// the welcome's purpose step (the landing hero's `PurposeScreen`). A port of
/// `web/src/components/landing/checker-stage/PurposeCards.tsx`:
///
/// - Seven cards in the hairline grid (1pt gaps on a border-coloured ground,
///   24pt outer radius). Travel is the most common answer, so it spans both
///   columns, leads, and carries the inset photo.
/// - Each card: the purpose glyph in its map accent, the ↗ arrow top-right
///   (30% at rest), the title and one short line.
/// - The chosen card (`selection`) takes the ink fill. A pressed card takes the
///   surface tone and a 1pt ink ring while the others step back to 50%
///   (`PURPOSE_GRID_PENDING`).
/// - Cards rise in with the `stage-card-in` stagger (80 + 40·i ms), off under
///   Reduce Motion.
struct PurposeCardGrid: View {
    /// The chosen purpose (welcome step); nil on Home, where no card is chosen.
    var selection: Purpose? = nil
    /// Gets the "Your goal" pill (the account's onboarding goal).
    var suggested: Purpose? = nil
    let onChoose: (Purpose) -> Void

    @State private var pressed: Purpose?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gap: CGFloat = Hairline.width

    var body: some View {
        let rest = Array(Purpose.allCases.dropFirst())
        VStack(spacing: gap) {
            card(.travel, index: 0)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(0..<(rest.count / 2), id: \.self) { row in
                HStack(spacing: gap) {
                    card(rest[row * 2], index: row * 2 + 1)
                    card(rest[row * 2 + 1], index: row * 2 + 2)
                }
                // Both cards in a row share the taller one's height.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Theme.border)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Hairline.width)
        )
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Purpose of your trip"))
    }

    private func card(_ purpose: Purpose, index: Int) -> some View {
        let active = purpose == selection
        let isPressed = purpose == pressed
        let dimmed = pressed != nil && !isPressed
        return Button { onChoose(purpose) } label: {
            PurposeCard(purpose: purpose, active: active, pressed: isPressed,
                        suggested: purpose == suggested)
        }
        .buttonStyle(PurposeCardPressStyle { down in
            if down { pressed = purpose } else if pressed == purpose { pressed = nil }
        })
        .opacity(dimmed ? 0.5 : 1)
        .animation(.easeOut(duration: 0.2), value: dimmed)
        // stage-card-in: fade up 12pt, 0.5s, cubic-bezier(0.2, 0.7, 0.2, 1).
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .animation(
            reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.5)
                .delay(0.08 + Double(index) * 0.04),
            value: appeared
        )
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("purpose.\(purpose.rawValue)")
    }
}

/// Reports press changes to the grid so the other cards can step back.
private struct PurposeCardPressStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in onPress(down) }
    }
}

/// One card's contents (`purposeCardClass` + `PurposeCardBody`).
private struct PurposeCard: View {
    let purpose: Purpose
    let active: Bool
    let pressed: Bool
    let suggested: Bool

    var body: some View {
        Group {
            if purpose == .travel {
                HStack(spacing: Spacing.sm) {
                    PurposePhoto()
                    content
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(Spacing.sm)
            } else {
                content
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? Theme.ink : (pressed ? Theme.surface : Theme.bg))
        .overlay {
            if pressed && !active {
                Rectangle().strokeBorder(Theme.ink, lineWidth: Hairline.width)
            }
        }
        .foregroundStyle(active ? Theme.inkInverse : Theme.ink)
        .contentShape(Rectangle())
    }

    private var content: some View {
        // `justify-between gap-6`: at least 24pt between the glyph row and the text.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                // Borderless glyph, full size, in its purpose's map accent,
                // fixed whatever is chosen.
                PurposeIcon(purpose: purpose, size: 32)
                    .foregroundStyle(RoutePalette.accent(purpose))
                Spacer(minLength: 0)
                HStack(spacing: Spacing.sm) {
                    if suggested {
                        Text("Your goal")
                            .font(.custom("Geist-Medium", size: 11))
                            .foregroundStyle(active ? Theme.inkInverse.opacity(0.7) : Theme.inkMuted)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Hairline.width))
                    }
                    CardArrow()
                        .frame(width: 16, height: 16)
                        .opacity(active ? 0.8 : (pressed ? 1 : 0.3))
                        // Pearl-style arrow: turns to point right on press.
                        .rotationEffect(.degrees(pressed ? -45 : 0))
                        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.28), value: pressed)
                }
            }
            Spacer(minLength: Spacing.xl)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(purpose.title)
                    .font(.custom("Geist-Medium", size: 17))
                    .tracking(-0.17)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(purpose.short)
                    .font(.custom("Geist-Regular", size: 12))
                    .lineSpacing(1.5)
                    .foregroundStyle(active ? AnyShapeStyle(Theme.inkInverse.opacity(0.7)) : AnyShapeStyle(Theme.textSoft))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
        }
    }
}

/// The travel card's decorative inset photo (`PhotoFrame`: 16pt radius,
/// hairline border, surface-2 ground while it loads).
private struct PurposePhoto: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 108, maxHeight: .infinity)
            .background(Theme.surface2)
            .overlay {
                Image("purpose-rio")
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Hairline.width)
            )
    }
}

/// The web `ArrowIcon` (↗ on a 16-unit grid, 1.5 stroke).
struct CardArrow: View {
    var body: some View {
        ArrowShape()
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private struct ArrowShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 16
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var p = Path()
            p.move(to: pt(3.5, 12.5)); p.addLine(to: pt(12.5, 3.5))
            p.move(to: pt(12.5, 3.5)); p.addLine(to: pt(5.5, 3.5))
            p.move(to: pt(12.5, 3.5)); p.addLine(to: pt(12.5, 10.5))
            return p
        }
    }
}

#Preview {
    ScrollView {
        PurposeCardGrid(suggested: .study) { _ in }
            .padding(Spacing.xl)
    }
    .background(Theme.bg)
}
