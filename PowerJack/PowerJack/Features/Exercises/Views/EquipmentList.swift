import SwiftData
import SwiftUI

struct EquipmentList: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomEquipment.name) private var allCustom: [CustomEquipment]
    var title = "Equipment"
    /// Custom equipment to leave out, by name, like the equipment being replaced.
    var excluding: String? = nil
    /// Picks equipment instead of opening it. Without it, rows open their details.
    var onSelect: ((Equipment, String?) -> Void)? = nil

    @State private var creating = false
    @State private var created: CustomEquipment?
    @State private var deleting: CustomEquipment?

    /// Own equipment, minus any that matches a built-in option.
    private var custom: [CustomEquipment] {
        allCustom.filter { item in
            item.name != excluding
                && !ExerciseCatalog.equipmentOptions.contains(.init(base: item.base, name: item.name))
        }
    }

    var body: some View {
        List {
            Button("Create equipment", systemImage: "plus") { creating = true }
            if !custom.isEmpty {
                Section("Your equipment") {
                    ForEach(custom) { item in
                        customRow(item)
                    }
                }
            }
            ForEach(ExerciseCatalog.equipmentOptionsByType, id: \.base) { group in
                Section(group.base.displayName) {
                    ForEach(group.options, id: \.self) { option in
                        builtInRow(option)
                    }
                }
            }
        }
        .navigationTitle(title)
        .sheet(isPresented: $creating, onDismiss: {
            if let created {
                self.created = nil
                select(created.base, name: created.name)
            }
        }) {
            NewEquipmentView { created = $0 }
        }
        .equipmentDeletion($deleting)
    }

    @ViewBuilder
    private func customRow(_ item: CustomEquipment) -> some View {
        if onSelect != nil {
            Button(item.name) { select(item.base, name: item.name) }
        } else {
            NavigationLink(item.name) { EquipmentDetail(custom: item) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // No destructive role: it removes the row before the user confirms.
                    Button("Delete", systemImage: "trash") { deleting = item }
                        .tint(.red)
                }
        }
    }

    @ViewBuilder
    private func builtInRow(_ option: ExerciseCatalog.EquipmentOption) -> some View {
        if onSelect != nil {
            Button(option.displayName) { select(option.base, name: option.name) }
        } else if option.base.hasLoadStep {
            NavigationLink(option.displayName) { EquipmentDetail(base: option.base, name: option.name) }
        } else {
            // Bodyweight types have nothing to set.
            Text(option.displayName)
        }
    }

    private func select(_ base: Equipment, name: String?) {
        guard let onSelect else { return }
        onSelect(base, name)
        dismiss()
    }
}

private struct NewEquipmentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [CustomEquipment]
    let saved: (CustomEquipment) -> Void
    @State private var name = ""
    @State private var base = Equipment.machine
    @State private var saveError: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool {
        let names = ExerciseCatalog.equipmentOptions.map(\.displayName) + existing.map(\.name)
        return names.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Equipment name", text: $name)
                        .onChange(of: name) { _, value in
                            if value.count > CustomEquipment.nameLimit {
                                name = String(value.prefix(CustomEquipment.nameLimit))
                            }
                        }
                } footer: {
                    Text(nameTaken ? "This equipment name already exists." : "\(name.count) of \(CustomEquipment.nameLimit) characters")
                }
                Section {
                    Picker("Equipment type", selection: $base) {
                        ForEach(Equipment.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text("PowerJack uses this type for weight increments and bodyweight tracking.")
                }
            }
            .navigationTitle("New Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let item = CustomEquipment(name: trimmed, base: base)
                        do {
                            try context.insertAndSave(item)
                            saved(item)
                            dismiss()
                        } catch { saveError = error.localizedDescription }
                    }
                    .disabled(trimmed.isEmpty || trimmed.contains(where: \.isNewline) || trimmed.count > CustomEquipment.nameLimit || nameTaken)
                }
            }
            .saveErrorAlert($saveError)
        }
    }
}
