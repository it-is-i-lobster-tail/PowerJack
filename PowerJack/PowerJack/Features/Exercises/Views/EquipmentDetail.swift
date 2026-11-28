//
//  EquipmentDetail.swift
//  PowerJack
//
//  One piece of equipment: how it loads (even steps, or only the weights the lifter owns), which
//  plans round weights to, and for the lifter's own equipment, its type and a way to delete it.
//

import SwiftUI

struct EquipmentDetail: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.Key.weightUnit) private var weightUnit = WeightUnit.deviceDefault
    @State private var deleting: CustomEquipment?
    @FocusState private var addingWeight: Bool

    private let name: String
    private let base: Equipment
    private let custom: CustomEquipment?

    /// Built-in equipment. Named kinds like EZ Bar use their base type's load step.
    init(base: Equipment, name: String? = nil) {
        self.name = name ?? base.displayName
        self.base = base
        custom = nil
    }

    init(custom: CustomEquipment) {
        name = custom.name
        base = custom.base
        self.custom = custom
    }

    var body: some View {
        Form {
            Section {
                if custom != nil {
                    LabeledContent("Type", value: base.displayName)
                }
                if base.hasLoadStep {
                    LoadModePicker(equipment: base, unit: weightUnit)
                        .id(weightUnit)
                }
            } footer: {
                if base.hasLoadStep { Text(footer) }
            }

            if base.hasLoadStep {
                OwnedWeightsSection(equipment: base, unit: weightUnit, adding: $addingWeight)
                    .id(weightUnit)
            }

            if let custom {
                Section {
                    Button("Delete Equipment", role: .destructive) { deleting = custom }
                }
            }
        }
        // The number pad slides over this tab page, so the Add Weight row scrolls up above it.
        .keepsFocusAboveKeyboard(addingWeight ? OwnedWeightsSection.addRowID : nil)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .equipmentDeletion($deleting) { dismiss() }
        .traceScreen("Equipment Detail")
    }

    private var footer: String {
        var lines = ["How plans pick weights for this equipment."]
        if base == .dumbbell || base == .kettlebell { lines.append("Weights are per hand.") }
        if name != base.displayName { lines.append("Shared by all \(base.displayName) equipment.") }
        return lines.joined(separator: " ")
    }
}

/// Even Steps with its step, or Only These Weights. Kilograms and pounds keep their own choices.
struct LoadModePicker: View {
    let equipment: Equipment
    let unit: WeightUnit
    @AppStorage private var mode: String

    init(equipment: Equipment, unit: WeightUnit) {
        self.equipment = equipment
        self.unit = unit
        _mode = AppStorage(wrappedValue: LoadMode.evenSteps.rawValue, OwnedLoads.modeKey(for: equipment, in: unit))
    }

    var body: some View {
        Picker("Loads", selection: $mode) {
            ForEach(LoadMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        if mode != LoadMode.ownedWeights.rawValue {
            LoadStepPicker(equipment: equipment, unit: unit)
        }
    }
}

/// The weights the lifter owns, lightest first, shown while Only These Weights is picked.
private struct OwnedWeightsSection: View {
    static let addRowID = "addWeight"

    let equipment: Equipment
    let unit: WeightUnit
    @AppStorage private var mode: String
    @AppStorage private var saved: String
    @State private var newWeight = ""
    var adding: FocusState<Bool>.Binding

    init(equipment: Equipment, unit: WeightUnit, adding: FocusState<Bool>.Binding) {
        self.equipment = equipment
        self.unit = unit
        self.adding = adding
        _mode = AppStorage(wrappedValue: LoadMode.evenSteps.rawValue, OwnedLoads.modeKey(for: equipment, in: unit))
        _saved = AppStorage(wrappedValue: "", OwnedLoads.weightsKey(for: equipment, in: unit))
    }

    private var weights: [Double] { OwnedLoads.decode(saved, in: unit) }

    /// The typed weight, in hundredths, when it's one a set can log and isn't on the list yet.
    private var typed: Double? {
        guard let value = try? Double(newWeight, format: .number), value.isFinite else { return nil }
        let rounded = (value * 100).rounded() / 100
        guard rounded > 0, rounded <= unit.maxEntry, !weights.contains(rounded) else { return nil }
        return rounded
    }

    var body: some View {
        if mode == LoadMode.ownedWeights.rawValue {
            Section {
                ForEach(weights, id: \.self) { weight in
                    Text(format(weight))
                }
                .onDelete { offsets in
                    var kept = weights
                    kept.remove(atOffsets: offsets)
                    saved = OwnedLoads.encode(kept)
                }

                HStack {
                    TextField("Add Weight", text: $newWeight)
                        .keyboardType(.decimalPad)
                        .focused(adding)
                    if !newWeight.isEmpty {
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                    Button("Add", action: add)
                        .disabled(typed == nil)
                }
                .id(Self.addRowID)
            } header: {
                Text("Weights")
            } footer: {
                Text(footer)
            }
            .onChange(of: adding.wrappedValue) { _, isAdding in
                if !isAdding { add() }
            }
        }
    }

    private var footer: String {
        weights.isEmpty
            ? "Add the weights you own. Until then, plans use even steps."
            : "Plans only use these weights. You can still log any weight."
    }

    private func add() {
        guard let typed else { return }
        saved = OwnedLoads.encode(weights + [typed])
        newWeight = ""
    }

    private func format(_ weight: Double) -> String {
        "\(weight.formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)"
    }
}

/// Picks the load step for one kind of equipment in one unit. Kilograms and pounds keep their own steps.
struct LoadStepPicker: View {
    let equipment: Equipment
    let unit: WeightUnit
    @AppStorage private var step: Double

    init(equipment: Equipment, unit: WeightUnit) {
        self.equipment = equipment
        self.unit = unit
        _step = AppStorage(
            wrappedValue: StrengthLoadSteps.defaultStep(for: equipment, in: unit) ?? 0,
            StrengthLoadSteps.key(for: equipment, in: unit)
        )
    }

    var body: some View {
        Picker("Load Step", selection: $step) {
            ForEach(StrengthLoadSteps.options(for: equipment, in: unit), id: \.self) { option in
                Text("\(option.formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)")
                    .tag(option)
            }
        }
    }
}

#Preview("Barbell") {
    NavigationStack { EquipmentDetail(base: .barbell) }
}
