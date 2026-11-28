//
//  EquipmentDeletion.swift
//  PowerJack
//
//  Asks before deleting the lifter's own equipment. Exercises that use it move to a replacement first.
//

import SwiftData
import SwiftUI

extension View {
    /// Starts deleting `equipment` whenever it's set. `deleted` runs once it's gone.
    func equipmentDeletion(_ equipment: Binding<CustomEquipment?>, deleted: @escaping () -> Void = {}) -> some View {
        modifier(EquipmentDeletion(request: equipment, deleted: deleted))
    }
}

private struct EquipmentDeletion: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var request: CustomEquipment?
    let deleted: () -> Void

    @State private var pending: CustomEquipment?
    // Copied, so nothing reads the model once it's deleted.
    @State private var name = ""
    @State private var userCount = 0
    @State private var choosingReplacement = false
    @State private var saveError: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, equipment in
                guard let equipment else { return }
                request = nil
                do {
                    userCount = try equipment.exercises(in: context).count
                    name = equipment.name
                    pending = equipment
                } catch {
                    saveError = error.localizedDescription
                }
            }
            .alert(
                "Delete “\(name)”?",
                isPresented: Binding(
                    get: { pending != nil && !choosingReplacement },
                    set: { if !$0, !choosingReplacement { pending = nil } }
                ),
                presenting: pending
            ) { equipment in
                if userCount == 0 {
                    Button("Delete", role: .destructive) { delete(equipment, movingTo: nil) }
                } else {
                    Button("Choose Replacement…") { choosingReplacement = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(userCount == 0
                     ? "This can't be undone."
                     : "\(userCount == 1 ? "1 exercise uses" : "\(userCount) exercises use") \(name). Choose equipment to move them to. Their logged sets stay with them.")
            }
            .sheet(isPresented: $choosingReplacement, onDismiss: { pending = nil }) {
                NavigationStack {
                    EquipmentList(title: "Replace \(name)", excluding: name) { base, customName in
                        if let pending { delete(pending, movingTo: (base, customName)) }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { choosingReplacement = false }
                        }
                    }
                }
            }
            .saveErrorAlert($saveError)
    }

    private func delete(_ equipment: CustomEquipment, movingTo replacement: (base: Equipment, name: String?)?) {
        do {
            try equipment.delete(movingExercisesTo: replacement?.base, named: replacement?.name, in: context)
            deleted()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
