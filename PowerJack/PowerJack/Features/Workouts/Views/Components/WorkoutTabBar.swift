import SwiftUI

/// The workout's Programs tab contracts to a circle while Settings stays at the other edge.
struct WorkoutTabBar: View {
    let isCollapsed: Bool
    let select: (MainBrowserOption) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 23

    private static let expandedHeight: CGFloat = 62
    private static let topSpacing: CGFloat = 8
    static var reservedHeight: CGFloat { expandedHeight + topSpacing }
    private let compactHeight: CGFloat = 48
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let diameter = isCollapsed ? compactHeight : Self.expandedHeight
            let groupWidth = isCollapsed ? diameter : max(diameter, geometry.size.width - diameter - gap)
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tab(.programs)
                        if !isCollapsed {
                            tab(.templates)
                            tab(.volume)
                        }
                    }
                    .padding(isCollapsed ? 0 : 4)
                    .frame(width: groupWidth, height: diameter)
                    .clipShape(.capsule)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Spacer(minLength: gap)

                    Button { select(.settings) } label: {
                        Image(systemName: MainBrowserOption.settings.symbol)
                            .font(.system(size: min(iconSize + 1, 28), weight: .semibold))
                            .symbolVariant(.fill)
                            .frame(width: diameter, height: diameter)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .powerJackGlassCircle(interactive: true)
                    .accessibilityLabel("Settings")
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: Self.expandedHeight)
        .padding(.horizontal, 20)
        .padding(.top, Self.topSpacing)
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private func tab(_ tab: MainBrowserOption) -> some View {
        let selected = tab == .programs
        return Button { select(tab) } label: {
            VStack(spacing: 1) {
                Image(systemName: tab.symbol)
                    .symbolVariant(.fill)
                    .font(.system(size: min(iconSize, 28), weight: .semibold))
                if !isCollapsed {
                    Text(tab.rawValue)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected && !isCollapsed { Capsule().fill(.quaternary) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(isCollapsed ? "Expands the tab bar" : "")
    }
}
