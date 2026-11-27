//
//  SharedImportView.swift
//  PowerJack
//
//  Shown when a .powerjack file opens the app: what's in it, and one question per name clash.
//

import SwiftData
import SwiftUI

struct SharedImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State var sharedImport: SharedImport
    /// Called after saving, with the new template if the file held one.
    let onImported: (TemplateProgram?) -> Void

    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let template = sharedImport.template {
                    TemplateSummary(template: template, sharedImport: sharedImport)
                } else if let item = sharedImport.items.first {
                    ExerciseSummary(item: item)
                }

                if sharedImport.items.contains(where: \.asks) || (sharedImport.template != nil && sharedImport.items.contains(where: \.isNew)) {
                    Section {
                        ForEach($sharedImport.items) { $item in
                            if item.asks {
                                ClashRow(item: $item)
                            } else if item.isNew, sharedImport.template != nil {
                                ExerciseLabel(name: item.shared.name, detail: equipmentName(item.shared))
                            }
                        }
                    } header: {
                        if sharedImport.template != nil { Text("Exercises") }
                    } footer: {
                        if sharedImport.items.contains(where: \.asks) {
                            Text("Use Mine keeps one exercise, so your history and progress stay together.")
                        }
                    }
                }

                if sharedImport.hasNothingToAdd {
                    Section {
                        Label("You already have this exercise.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(sharedImport.template == nil ? "Import Exercise" : "Import Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sharedImport.hasNothingToAdd {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: dismiss.callAsFunction)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import", action: save)
                    }
                }
            }
            .saveErrorAlert($saveErrorMessage)
        }
        .traceScreen("Import")
    }

    private func save() {
        do {
            let template = try sharedImport.save(in: modelContext)
            TraceLog.record(.data, "Imported \(sharedImport.template == nil ? "an exercise" : "a template")")
            onImported(template)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private func equipmentName(_ shared: SharedExercise) -> String {
    shared.customEquipmentName ?? Equipment(rawValue: shared.equipment)?.displayName ?? ""
}

private func muscleName(_ raw: String) -> String {
    raw.localizedCapitalized
}

private struct ExerciseLabel: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TemplateSummary: View {
    let template: SharedTemplate
    let sharedImport: SharedImport

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        ForEach(Array(template.days.enumerated()), id: \.offset) { index, day in
            Section("Day \(index + 1)") {
                ForEach(Array(day.enumerated()), id: \.offset) { _, row in
                    if sharedImport.items.indices.contains(row.exercise) {
                        let shared = sharedImport.items[row.exercise].shared
                        ExerciseLabel(name: shared.name, detail: equipmentName(shared))
                    }
                }
            }
        }
    }

    private var summary: String {
        let type = TemplateType(rawValue: template.type)?.name ?? ""
        let days = "\(template.workoutsPerWeek) days/wk"
        let focus = template.muscleFocus.map(muscleName).joined(separator: ", ")
        return [type, days, focus].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ExerciseSummary: View {
    let item: SharedImport.Item

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.shared.name)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        let reps = "\(item.shared.minReps)–\(item.shared.maxReps) reps"
        return [equipmentName(item.shared), muscleName(item.shared.primaryMuscle), reps]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// A shared exercise with the name of one the lifter already has, set up differently.
private struct ClashRow: View {
    @Binding var item: SharedImport.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExerciseLabel(name: item.shared.name, detail: message)
            Picker(item.shared.name, selection: $item.choice) {
                Text("Use Mine").tag(SharedImport.Choice.useMine)
                Text("Keep Both").tag(SharedImport.Choice.keepBoth)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var message: String {
        switch item.choice {
        case .useMine: "You have one with this name, set up differently. Yours will be used."
        case .keepBoth: "Adds the shared one as \u{201C}\(item.keepBothName)\u{201D}."
        }
    }
}
