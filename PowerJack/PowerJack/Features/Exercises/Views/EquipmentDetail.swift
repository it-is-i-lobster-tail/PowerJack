//
//  EquipmentDetail.swift
//  PowerJack
//
//  One piece of equipment: its load step, which Strength rounds planned weights to,
//  and for the lifter's own equipment, its type and a way to delete it.
//

import SwiftUI

struct EquipmentDetail: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.Key.weightUnit) private var weightUnit = WeightUnit.deviceDefault
    @State private var deleting: CustomEquipment?

    private let name: String
    private let base: Equipment
    private let custom: CustomEquipment?

    init(base: Equipment) {
        name = base.displayName
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
                    LoadStepPicker(equipment: base, unit: weightUnit)
                        .id(weightUnit)
                }
            } footer: {
                if base.hasLoadStep { Text(footer) }
            }

            if let custom {
                Section {
                    Button("Delete Equipment", role: .destructive) { deleting = custom }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .equipmentDeletion($deleting) { dismiss() }
        .traceScreen("Equipment Detail")
    }

    private var footer: String {
        var lines = ["The smallest weight jump for this equipment. Used in Strength programs."]
        if base == .dumbbell || base == .kettlebell { lines.append("It's per hand.") }
        if custom != nil { lines.append("Shared by all \(base.displayName) equipment.") }
        return lines.joined(separator: " ")
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

extension Equipment {
    /// Bodyweight alone has no load, so it has no load step.
    var hasLoadStep: Bool { StrengthLoadSteps.defaultStep(for: self, in: .pounds) != nil }
}

#Preview("Barbell") {
    NavigationStack { EquipmentDetail(base: .barbell) }
}
