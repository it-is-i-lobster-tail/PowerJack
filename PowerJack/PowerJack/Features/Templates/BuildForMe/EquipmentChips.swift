//
//  EquipmentChips.swift
//  PowerJack
//
//  The Build for Me equipment row: a chip for each built-in kind, its named pieces (an EZ bar, the
//  lifter's own equipment) right after it, then the bench and pull-up bar. Tap a chip to turn it off.
//

import SwiftData
import SwiftUI

struct EquipmentChips: View {
    @Binding var choice: EquipmentChoice

    @Query(sort: \CustomEquipment.name) private var customEquipment: [CustomEquipment]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            FormFieldLabel(
                systemImage: "dumbbell",
                title: "Equipment",
                detail: "Tap what your gym doesn't have"
            )
            ChipFlow {
                ForEach(EquipmentItem.kinds, id: \.self) { kind in
                    EquipmentChip(title: kind.displayName, isOn: choice.isOn(kind)) {
                        choice.toggle(kind)
                    }
                    ForEach(pieces(of: kind), id: \.self) { piece in
                        EquipmentChip(title: piece, isOn: choice.isOn(piece: piece), isPiece: true) {
                            choice.toggle(piece: piece)
                        }
                        // A piece needs its kind: an EZ bar is no use with barbells off.
                        .disabled(!choice.isOn(kind))
                    }
                }
                ForEach(ExerciseFilters.Setup.allCases, id: \.self) { setup in
                    EquipmentChip(title: EquipmentItem.setup(setup).name, isOn: choice.isOn(setup)) {
                        choice.toggle(setup)
                    }
                }
            }
        }
        .padding(LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassCard(interactive: true)
    }

    /// The named pieces of a kind: the built-in ones first, then the lifter's own.
    private func pieces(of kind: Equipment) -> [String] {
        let builtIn = ExerciseCatalog.equipmentOptions.filter { $0.base == kind }.compactMap(\.name)
        let own = customEquipment.filter { ($0.base == .loadableBodyweight ? .bodyweight : $0.base) == kind }.map(\.name)
        var seen = Set<String>()
        return (builtIn + own).filter { seen.insert($0).inserted }
    }
}

private struct EquipmentChip: View {
    let title: String
    let isOn: Bool
    var isPiece = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isPiece ? .caption : .subheadline)
                .padding(.horizontal, isPiece ? 10 : 12)
                .padding(.vertical, isPiece ? 5 : 7)
                .foregroundStyle(isOn ? .white : .secondary)
                .background(isOn ? Color.blue.opacity(isPiece ? 0.7 : 1) : Color.secondary.opacity(0.15), in: .capsule)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Lays its views out in rows, wrapping to the next row when one is full.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = frames(for: subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
