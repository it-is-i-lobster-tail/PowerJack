//
//  LoadStepsView.swift
//  PowerJack
//
//  The smallest weight jump per kind of equipment, which Strength rounds every planned weight to.
//

import SwiftUI

struct LoadStepsView: View {
    @AppStorage(AppSettings.Key.weightUnit) private var weightUnit = WeightUnit.deviceDefault

    var body: some View {
        Form {
            Section {
                ForEach(Equipment.allCases.filter { $0 != .bodyweight }) { equipment in
                    LoadStepRow(equipment: equipment, unit: weightUnit)
                        .id("\(equipment.rawValue).\(weightUnit.rawValue)")
                }
            } footer: {
                Text("Strength rounds every planned weight to these steps. Dumbbell and kettlebell steps are per hand. Kilograms and pounds keep their own steps.")
            }
        }
        .navigationTitle("Load Steps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LoadStepRow: View {
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
        Picker(equipment.displayName, selection: $step) {
            ForEach(StrengthLoadSteps.options(for: equipment, in: unit), id: \.self) { option in
                Text("\(option.formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)")
                    .tag(option)
            }
        }
    }
}

private extension Equipment {
    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .bodyweight: "Bodyweight"
        case .cable: "Cable"
        case .machine: "Machine"
        case .kettlebell: "Kettlebell"
        case .legPress: "Leg Press"
        }
    }
}

#Preview("Load Steps") {
    NavigationStack {
        LoadStepsView()
    }
}
