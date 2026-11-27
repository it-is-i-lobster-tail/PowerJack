import SwiftUI

/// The Edit Exercise row that opens Advanced Data. Its detail names the joints the lift works.
struct ExerciseAdvancedDataLink: View {
    @Binding var draft: ExerciseDraft
    let height: CGFloat

    private var detail: String {
        let worked = Set(JointInvolvement.of(draft.jointActions).keys.compactMap { $0.split(separator: ".").first.map(String.init) })
        let names = JointAnatomy.bundled.joints.filter { worked.contains($0.key) }.map(\.name)
        return names.isEmpty ? "No joints set" : names.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink {
            ExerciseAdvancedDataView(draft: $draft)
        } label: {
            HStack {
                FormFieldLabel(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: "Advanced Data",
                    detail: LocalizedStringKey(detail)
                )
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(height: height)
        .powerJackGlassCard(interactive: true)
        .accessibilityHint("Shows the joints, movements and muscles this exercise works")
    }
}

/// Every joint, the movements it can do and the muscles behind each one, with how this lift
/// uses them. The lifter's own exercises can change that; built-ins only show it.
struct ExerciseAdvancedDataView: View {
    @Binding var draft: ExerciseDraft

    /// Joint order, set when the screen opens so a card doesn't jump while it's being edited.
    @State private var order: [String] = []

    private let anatomy = JointAnatomy.bundled

    private var involvement: [String: JointInvolvement] { JointInvolvement.of(draft.jointActions) }

    private var joints: [JointAnatomy.Joint] {
        let byKey = Dictionary(uniqueKeysWithValues: anatomy.joints.map { ($0.key, $0) })
        return order.isEmpty ? anatomy.joints : order.compactMap { byKey[$0] }
    }

    /// Joints the lift works come first, each group in body order.
    private var workedFirst: [JointAnatomy.Joint] {
        let used = involvement
        let (worked, rest) = anatomy.joints.reduce(into: ([JointAnatomy.Joint](), [JointAnatomy.Joint]())) { groups, joint in
            if joint.movementKeys.contains(where: { used[$0] != nil }) {
                groups.0.append(joint)
            } else {
                groups.1.append(joint)
            }
        }
        return worked + rest
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
                VStack(spacing: LayoutMetrics.sectionSpacing) {
                    note
                    ForEach(joints, id: \.key) { joint in
                        card(for: joint)
                    }
                }
                .padding(LayoutMetrics.sectionSpacing)
            }
        }
        .onAppear { if order.isEmpty { order = workedFirst.map(\.key) } }
        .navigationTitle("Advanced Data")
        .navigationBarTitleDisplayMode(.inline)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var note: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text(draft.isBuiltIn
                 ? "Built-in exercises show their joints read only."
                 : "Set how this exercise uses each joint. Search uses it to find lifts that move alike.")
                .font(.caption)
            Spacer()
        }
    }

    private func card(for joint: JointAnatomy.Joint) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(joint.name).font(.headline)
                Spacer()
                Text(JointAnatomy.name(ofMovement: joint.type.rawValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(joint.movementKeys, id: \.self) { movement in
                Divider()
                row(for: movement)
            }
        }
        .padding(LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassCard()
    }

    private func row(for movement: String) -> some View {
        let movers = anatomy.muscles(for: movement).sorted { $0.name < $1.name }
        let prime = movers.filter(\.isPrime).map { Self.muscleName($0.name) }
        let helpers = movers.filter { !$0.isPrime }.map { Self.muscleName($0.name) }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(JointAnatomy.name(ofMovement: movement))
                if !prime.isEmpty {
                    Text(prime.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !helpers.isEmpty {
                    Text("Helped by \(helpers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            value(for: movement)
        }
        .accessibilityElement(children: draft.isBuiltIn ? .combine : .contain)
    }

    @ViewBuilder
    private func value(for movement: String) -> some View {
        let current = involvement[movement]
        if draft.isBuiltIn {
            Text(current?.name ?? "—")
                .font(.subheadline.weight(current == nil ? .regular : .semibold))
                .foregroundStyle(current == nil ? .secondary : .primary)
        } else {
            Menu {
                Picker(JointAnatomy.name(ofMovement: movement), selection: Binding(
                    get: { current },
                    set: { draft.setJoint(movement, to: $0) }
                )) {
                    Text("Not used").tag(JointInvolvement?.none)
                    ForEach(JointInvolvement.allCases) { involvement in
                        Text(involvement.name).tag(Optional(involvement))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current?.name ?? "Not used")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(current == nil ? .regular : .semibold))
                .foregroundStyle(current == nil ? Color.secondary : Color.accentColor)
            }
            .accessibilityLabel(JointAnatomy.name(ofMovement: movement))
            .accessibilityValue(current?.name ?? "Not used")
        }
    }

    /// "anterior deltoid" reads "Anterior deltoid".
    private static func muscleName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
}

#Preview("Advanced Data - own exercise") {
    @Previewable @State var draft = ExerciseDraft(name: "Landmine Row")
    NavigationStack {
        ExerciseAdvancedDataView(draft: $draft)
    }
}
