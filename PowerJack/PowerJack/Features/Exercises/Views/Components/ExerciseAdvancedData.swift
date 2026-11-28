import SwiftUI

/// The New and Edit Exercise row that opens Advanced Data.
struct ExerciseAdvancedDataLink: View {
    @Binding var draft: ExerciseDraft
    let height: CGFloat

    /// "Moves like Dumbbell Lateral Raise" once lifts are picked, else the joints it works.
    static func detail(for draft: ExerciseDraft) -> String {
        if draft.customActions == nil, let names = draft.movesLikeName { return "Moves like \(names)" }
        return ExerciseJointsView.summary(of: draft)
    }

    var body: some View {
        AdvancedDataRow(
            systemImage: "point.3.connected.trianglepath.dotted",
            title: "Advanced Data",
            detail: Self.detail(for: draft),
            height: height
        ) {
            ExerciseAdvancedDataView(draft: $draft)
        }
        .accessibilityHint("Shows what this exercise moves like and the joints it works")
    }
}

/// What the exercise moves like and the joints it works, each on its own page.
struct ExerciseAdvancedDataView: View {
    @Binding var draft: ExerciseDraft

    private let rowHeight: CGFloat = 85

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
                VStack(spacing: LayoutMetrics.sectionSpacing) {
                    FormInfoNote(draft.isBuiltIn
                                 ? "Details search and charts use to match this exercise to similar lifts."
                                 : "Details that help search and charts match this exercise to similar lifts.")
                    // Built-in exercises get their movement from the catalog.
                    if !draft.isBuiltIn {
                        AdvancedDataRow(
                            systemImage: "figure.strengthtraining.traditional",
                            title: "Moves Like",
                            detail: draft.movesLikeName ?? "Not set",
                            height: rowHeight
                        ) {
                            // Joint actions set by hand match no lift, so none is picked.
                            MovesLikeList(picks: draft.customActions == nil ? draft.movesLike : []) {
                                draft.choose(movesLike: $0)
                            }
                        }
                        .accessibilityHint("Picks up to three built-in exercises this one moves like")
                    }
                    AdvancedDataRow(
                        systemImage: "figure.arms.open",
                        title: "Joints",
                        detail: ExerciseJointsView.summary(of: draft),
                        height: rowHeight
                    ) {
                        ExerciseJointsView(draft: $draft)
                    }
                    .accessibilityHint("Shows the joints, movements and muscles this exercise works")
                }
                .padding(LayoutMetrics.sectionSpacing)
            }
        }
        .navigationTitle("Advanced Data")
        .navigationBarTitleDisplayMode(.inline)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

/// A glass row that pushes a page: icon, title, one line of detail and a chevron.
private struct AdvancedDataRow<Destination: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: String
    let height: CGFloat
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                FormFieldLabel(systemImage: systemImage, title: title, detail: LocalizedStringKey(detail))
                    .lineLimit(1)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(height: height)
        .powerJackGlassCard(interactive: true)
    }
}

/// Every joint, the movements it can do and the muscles behind each one, with how this lift
/// uses them. The lifter's own exercises can change that; built-ins only show it.
struct ExerciseJointsView: View {
    @Binding var draft: ExerciseDraft

    /// Joint order and open cards, set when the screen opens so a card doesn't jump or close
    /// while it's being edited.
    @State private var order: [String] = []
    @State private var expanded: Set<String> = []

    private let anatomy = JointAnatomy.bundled

    private var involvement: [String: JointInvolvement] { JointInvolvement.of(draft.jointActions) }

    private var joints: [JointAnatomy.Joint] {
        let byKey = Dictionary(uniqueKeysWithValues: anatomy.joints.map { ($0.key, $0) })
        return order.isEmpty ? anatomy.joints : order.compactMap { byKey[$0] }
    }

    /// The worked joints' names, such as "Shoulder, Elbow", or "No joints set".
    static func summary(of draft: ExerciseDraft) -> String {
        let worked = workedJoints(in: draft.jointActions)
        let names = JointAnatomy.bundled.joints.filter { worked.contains($0.key) }.map(\.name)
        return names.isEmpty ? "No joints set" : names.joined(separator: ", ")
    }

    /// The joints with at least one movement these actions use.
    static func workedJoints(in actions: [JointAction], anatomy: JointAnatomy = .bundled) -> Set<String> {
        let used = JointInvolvement.of(actions)
        return Set(anatomy.joints.filter { $0.movementKeys.contains { used[$0] != nil } }.map(\.key))
    }

    /// Worked joints come first and open, each group in body order.
    private func arrange() {
        let worked = Self.workedJoints(in: draft.jointActions, anatomy: anatomy)
        let keys = anatomy.joints.map(\.key)
        order = keys.filter(worked.contains) + keys.filter { !worked.contains($0) }
        expanded = worked
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
                VStack(spacing: LayoutMetrics.sectionSpacing) {
                    FormInfoNote(draft.isBuiltIn
                                 ? "Built-in exercises show their joints read only."
                                 : "Set how this exercise uses each joint. Search uses it to find lifts that move alike.")
                    ForEach(joints, id: \.key) { joint in
                        card(for: joint)
                    }
                }
                .padding(LayoutMetrics.sectionSpacing)
            }
        }
        .onAppear { if order.isEmpty { arrange() } }
        .navigationTitle("Joints")
        .navigationBarTitleDisplayMode(.inline)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func card(for joint: JointAnatomy.Joint) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(joint.key) },
            set: { isOpen in
                if isOpen { expanded.insert(joint.key) } else { expanded.remove(joint.key) }
            }
        )) {
            VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                ForEach(joint.movementKeys, id: \.self) { movement in
                    Divider()
                    row(for: movement)
                }
            }
            .padding(.top, LayoutMetrics.compactSpacing)
        } label: {
            // The header reads as a title, not a tinted button.
            HStack(alignment: .firstTextBaseline) {
                Text(joint.name).font(.headline)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(JointAnatomy.name(ofMovement: joint.type.rawValue))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
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

/// The built-in exercises, searchable. The lifter picks up to three this one moves like,
/// closest first, or None.
struct MovesLikeList: View {
    let onChange: ([String]) -> Void

    @State private var picks: [String]
    @State private var searchText = ""

    init(picks: [String], onChange: @escaping ([String]) -> Void) {
        _picks = State(initialValue: picks)
        self.onChange = onChange
    }

    private var isFull: Bool { picks.count >= MovesLike.maxPicks }

    private var shown: [ExerciseCatalog.Entry] {
        let query = ExerciseQuery(searchText)
        guard !query.isEmpty else {
            return ExerciseCatalog.entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return MovesLike.index.rank(query).compactMap { MovesLike.entry($0.key) }
    }

    var body: some View {
        List {
            if searchText.isEmpty && !picks.isEmpty {
                Section {
                    ForEach(Array(picks.enumerated()), id: \.element) { place, key in
                        if let entry = MovesLike.entry(key) {
                            HStack(spacing: 12) {
                                Text("\(place + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .monospacedDigit()
                                label(entry.name, detail: detail(of: entry))
                            }
                        }
                    }
                    .onMove { picks.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { picks.remove(atOffsets: $0) }
                } header: {
                    Text("Picked · \(picks.count) of \(MovesLike.maxPicks)")
                } footer: {
                    Text(isFull ? "Remove one to pick another." : "Pick up to \(MovesLike.maxPicks), closest first.")
                }
            }
            Section {
                if searchText.isEmpty {
                    row("None", detail: nil, isPicked: picks.isEmpty) { picks = [] }
                }
                ForEach(shown, id: \.id) { entry in
                    let key = "catalog:\(entry.id)"
                    let isPicked = picks.contains(key)
                    row(entry.name, detail: detail(of: entry), isPicked: isPicked) {
                        if isPicked { picks.removeAll { $0 == key } } else { picks.append(key) }
                    }
                    .disabled(isFull && !isPicked)
                }
            } header: {
                if searchText.isEmpty && picks.isEmpty {
                    Text("Pick up to \(MovesLike.maxPicks), closest first")
                }
            }
        }
        .overlay {
            if !searchText.isEmpty && shown.isEmpty {
                EmptyStateView(title: "No matching exercises", systemImage: "magnifyingglass")
            }
        }
        .toolbar {
            if searchText.isEmpty && picks.count > 1 { EditButton() }
        }
        .onChange(of: picks) { onChange(picks) }
        .navigationTitle("Moves Like")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search built-in exercises")
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func detail(of entry: ExerciseCatalog.Entry) -> String {
        entry.equipmentName ?? entry.equipment.displayName
    }

    private func label(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, detail: String?, isPicked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                label(title, detail: detail)
                Spacer()
                if isPicked {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Advanced Data - own exercise") {
    @Previewable @State var draft = ExerciseDraft(name: "Landmine Row")
    NavigationStack {
        ExerciseAdvancedDataView(draft: $draft)
    }
}
