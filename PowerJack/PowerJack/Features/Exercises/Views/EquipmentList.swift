import SwiftData
import SwiftUI

struct EquipmentList: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomEquipment.name) private var custom: [CustomEquipment]
    var onSelect: ((Equipment, String?) -> Void)? = nil

    @State private var creating = false
    @State private var created: CustomEquipment?

    private var customOptions: [CustomEquipment] {
        custom.filter { item in
            !ExerciseCatalog.equipmentOptions.contains(.init(base: item.base, name: item.name))
        }
    }

    var body: some View {
        List {
            Button("Create equipment", systemImage: "plus") { creating = true }
            if !customOptions.isEmpty {
                Section("Your equipment") {
                    ForEach(customOptions) { item in
                        row(item.name, base: item.base, customName: item.name)
                    }
                }
            }
            Section("Built-in equipment") {
                ForEach(ExerciseCatalog.equipmentOptions, id: \.self) { option in
                    row(option.displayName, base: option.base, customName: option.name)
                }
            }
        }
        .navigationTitle("Equipment")
        .sheet(isPresented: $creating, onDismiss: {
            if let created {
                self.created = nil
                select(created.base, name: created.name)
            }
        }) {
            NewEquipmentView { created = $0 }
        }
    }

    @ViewBuilder
    private func row(_ title: String, base: Equipment, customName: String?) -> some View {
        if onSelect != nil {
            Button(title) { select(base, name: customName) }
        } else {
            Text(title)
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
