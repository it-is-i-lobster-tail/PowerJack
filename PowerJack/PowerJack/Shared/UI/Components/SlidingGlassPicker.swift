//
//  SlidingGlassPicker.swift
//  PowerJack
//
//  Created by trogdor on 7/22/26.
//

import SwiftUI

struct BrowserOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let index: Int
}

struct SlidingGlassPicker<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// Called on every tap, including a tap on the option that's already selected.
    var onTap: (Option) -> Void = { _ in }
    /// Pads the outer options to the same width, so the middle one sits on the picker's center.
    var centersMiddleOption = false

    @Namespace private var animation

    var body: some View {
        let layout = centersMiddleOption ? AnyLayout(MirroredHStack(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))

        layout {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy) {
                        selection = option
                    }
                    onTap(option)
                } label: {
                    Text(title(option))
                        .font(.default)
                        .fontWeight(.regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        // Fills the width a mirrored row gives it, so the selection pill does too.
                        .frame(maxWidth: centersMiddleOption ? .infinity : nil, minHeight: 44)
                        // The whole pill is tappable, not just the letters.
                        .contentShape(Capsule())
                        .background {
                            if selection == option {
                                Color.clear
                                    .glassEffect(.regular, in: Capsule())
                                    .matchedGeometryEffect(
                                        id: "selection",
                                        in: animation
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                // Lets an outer view point a hint at this option.
                .hintAnchor(String(describing: option.id))
            }
        }
        .padding(4)
        .powerJackGlassSelection()
        .onChange(of: options) { _, newOptions in
            if !newOptions.contains(selection),
               let first = newOptions.first {
                selection = first
            }
        }
    }
}

/// A row where each view is as wide as its mirror image (first and last, second and second to last),
/// so the middle view, or the middle gap, sits on the row's center.
private struct MirroredHStack: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = mirroredWidths(of: subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: widths.reduce(0, +) + gaps, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, mirroredWidths(of: subviews)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func mirroredWidths(of subviews: Subviews) -> [CGFloat] {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return widths.indices.map { max(widths[$0], widths[widths.count - 1 - $0]) }
    }
}
