//
//  YourDataSettingsView.swift
//  PowerJack
//
//  Where your training is kept: iCloud Backup, and exporting your history.
//

import SwiftData
import SwiftUI

struct YourDataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PowerJackStore.self) private var store

    @State private var iCloudAvailable = true
    @State private var isConfirmingICloudOff = false
    @State private var isDeletingICloudCopy = false
    @State private var showsICloudOffError = false
    @State private var isConfirmingExport = false
    @State private var exportedHistory: URL?
    @State private var isSharingHistory = false
    @State private var showsExportError = false

    var body: some View {
        content.traceScreen("Your Data")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                Toggle(isOn: iCloudBackup) {
                    SettingsRowLabel(
                        systemImage: "icloud",
                        title: "iCloud Backup",
                        detail: "Keeps your programs, templates and workout history in your private iCloud, so a new iPhone or a reinstall picks up where you left off. Only you can see it."
                    )
                }
                .disabled(isDeletingICloudCopy)
            } footer: {
                if isDeletingICloudCopy {
                    Text("Deleting your iCloud copy…")
                } else if store.syncsWithICloud, !iCloudAvailable {
                    Text("Sign in to iCloud in iOS Settings to start backing up.")
                }
            }

            // Its own card, so the iCloud note above stays with iCloud Backup.
            Section {
                Button {
                    isConfirmingExport = true
                } label: {
                    SettingsRowLabel(
                        systemImage: "square.and.arrow.up",
                        title: "Export Workout History",
                        detail: "Every set you've logged, as a spreadsheet file (CSV)."
                    )
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Your Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Turn Off iCloud Backup?", isPresented: $isConfirmingICloudOff) {
            Button("Yes, Turn Off", role: .destructive, action: turnOffICloudBackup)
            Button("No", role: .cancel) {}
        } message: {
            Text("Your workouts stay on this iPhone, but the copy in iCloud will be deleted. A new iPhone or a reinstall won't get them back.")
        }
        .alert("Couldn't Turn Off iCloud Backup", isPresented: $showsICloudOffError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloud couldn't be reached, so nothing was deleted. Check your connection and try again.")
        }
        .alert("Export Workout History?", isPresented: $isConfirmingExport) {
            Button("Export", action: exportHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file has every workout, set, weight and time you've logged. Names you gave your own templates and exercises are left out. Anyone you send it to can read it, so only share it with people you trust.")
        }
        .alert("Couldn't Export", isPresented: $showsExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your workout history couldn't be read. Try again.")
        }
        .sheet(isPresented: $isSharingHistory, onDismiss: removeExportedHistory) {
            if let exportedHistory {
                ShareSheet(url: exportedHistory)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
        .task {
            iCloudAvailable = await store.iCloudAccountAvailable()
        }
    }

    // Turning backup off asks first, because it deletes the iCloud copy.
    private var iCloudBackup: Binding<Bool> {
        Binding(
            get: { store.syncsWithICloud },
            set: { isOn in
                if isOn {
                    store.turnOnICloudBackup()
                } else {
                    isConfirmingICloudOff = true
                }
            }
        )
    }

    private func turnOffICloudBackup() {
        isDeletingICloudCopy = true
        Task {
            do {
                try await store.turnOffICloudBackup()
            } catch {
                showsICloudOffError = true
            }
            isDeletingICloudCopy = false
        }
    }

    private func exportHistory() {
        do {
            exportedHistory = try HistoryExport.writeFile(from: modelContext)
            isSharingHistory = true
        } catch {
            showsExportError = true
        }
    }

    // The copy only lives as long as the share sheet, so the history isn't left lying around.
    private func removeExportedHistory() {
        guard let exportedHistory else { return }
        try? FileManager.default.removeItem(at: exportedHistory)
        self.exportedHistory = nil
    }
}

#Preview("Your Data") {
    NavigationStack { YourDataSettingsView() }
        .environment(PowerJackStore(inMemory: true))
}
