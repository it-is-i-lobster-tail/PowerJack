//
//  PowerJackRootView.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

import SwiftData
import SwiftUI
import TipKit

private enum MainBrowserOption: String {
    case programs = "Programs"
    case templates = "Templates"
    case data = "Data"
    case settings = "Settings"
}

struct PowerJackRootView: View {
    @Environment(\.modelContext) private var modelContext
    // Missing in previews, which never switch iCloud Backup.
    @Environment(PowerJackStore.self) private var store: PowerJackStore?

    // These contain no models and survive an iCloud Backup container switch.
    @State private var selection = MainBrowserOption.programs
    @State private var settingsPath = NavigationPath()

    var body: some View {
        Group {
            // Switching iCloud Backup replaces the container. The screens holding its models
            // come down first, then the new container opens and they rebuild from it.
            if store?.isReplacingContainer != true {
                PowerJackScreens(selection: $selection, settingsPath: $settingsPath)
                    .id(ObjectIdentifier(modelContext.container))
            } else {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .onChange(of: store?.isReplacingContainer, initial: true) { _, isReplacing in
                        guard isReplacing == true else { return }
                        store?.replaceContainer()
                    }
            }
        }
        .onChange(of: store?.isReplacingContainer) { _, _ in
            WorkoutReminders.shared.refresh()
        }
        .onChange(of: selection) { _, selection in
            TraceLog.record(.screen, "Switched to \(selection.rawValue)")
        }
    }
}

private struct PowerJackScreens: View {
    @Binding var selection: MainBrowserOption
    @Binding var settingsPath: NavigationPath

    @Query(filter: Program.ownRows) private var programs: [Program]

    private var activeProgram: Program? { programs.active }

    @State private var router = ProgramsRouter()
    @State private var didRestore = false
    // A workout fades the bars away while it sits idle.
    @State private var idleControls = IdleControls()
    // A shared template or exercise opened from another app.
    @State private var sharedImport: SharedImport?
    @State private var sharedImportError: String?
    @AppStorage(TemplateType.selectionKey) private var listedTemplateType: TemplateType = .hypertrophy

    @Environment(\.modelContext) private var modelContext

    private var showsWorkoutHeader: Bool {
        guard selection == .programs, case .session(let program) = router.path.last else { return false }
        return program == activeProgram && program.nextWorkout?.workoutExercises.isEmpty == false
    }

    private var settingsRole: TabRole? {
        // CI also builds with the iOS 26 SDK.
        #if compiler(>=6.4)
        if #available(iOS 27, *) { return .prominent }
        #endif
        return nil
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Programs", systemImage: "dumbbell", value: MainBrowserOption.programs) {
                NavigationStack(path: $router.path) {
                    ProgramListView()
                        .programRouteDestinations()
                }
                .powerJackTabPage()
            }

            Tab("Templates", systemImage: "square.stack.3d.up", value: MainBrowserOption.templates) {
                TemplateProgramListView()
                    .powerJackTabPage()
            }

            Tab("Data", systemImage: "chart.bar", value: MainBrowserOption.data) {
                ProgramDataView()
                    .powerJackTabPage()
            }

            Tab("Settings", systemImage: "gearshape", value: MainBrowserOption.settings, role: settingsRole) {
                NavigationStack(path: $settingsPath) {
                    SettingsView()
                        .traceScreen("Settings")
                }
                .powerJackTabPage()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .restTimer(inWorkoutHeader: showsWorkoutHeader, onOpenCurrentExercise: openCurrentExercise)
        .environment(router)
        .environment(idleControls)
        .powerJackKeyboardBehavior()
        .revealsIdleControlsOnTap(idleControls)
        .onChange(of: selection) { _, section in
            switch section {
            case .programs: ProgramsHint.opened.sendDonation()
            case .templates: WelcomeHint().invalidate(reason: .actionPerformed)
            case .data, .settings: break
            }
        }
        .onAppear(perform: restoreActiveWorkout)
        .onChange(of: WorkoutReminders.shared.previewRequest, initial: true) { _, _ in
            openRequestedPreview()
        }
        .onChange(of: router.path) { _, path in
            TraceLog.record(.screen, "Programs: \(path.isEmpty ? "My Programs" : path.map(\.traceName).joined(separator: " > "))")
        }
        .onOpenURL(perform: handleOpenURL)
        .sheet(item: $sharedImport) { sharedImport in
            SharedImportView(sharedImport: sharedImport, onImported: showImported)
        }
        .alert("Couldn't Open File", isPresented: Binding(
            get: { sharedImportError != nil },
            set: { if !$0 { sharedImportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharedImportError ?? "")
        }
    }

    /// On launch, and after an iCloud Backup switch, reopen the active program's current workout.
    private func restoreActiveWorkout() {
        guard !didRestore else { return }
        didRestore = true

        guard let activeProgram, activeProgram.nextWorkout != nil else { return }
        router.restore(activeProgram: activeProgram)
    }

    private func openRequestedPreview() {
        guard let requested = WorkoutReminders.shared.takePreviewRequest() else { return }
        didRestore = true
        selection = .programs
        guard let activeProgram, let workout = activeProgram.nextWorkout else {
            router.popToRoot()
            return
        }
        if workout.syncID == requested.workoutID, workout.status == .planned, !workout.workoutExercises.isEmpty {
            router.showPreview(workout, in: activeProgram, highlight: requested.highlight)
        } else {
            router.showDetailOnly(activeProgram)
        }
    }

    /// Takes the user to the exercise they should be doing, from the rest timer or its Live Activity.
    private func openCurrentExercise() {
        guard let activeProgram, activeProgram.nextWorkout != nil else { return }
        selection = .programs
        router.showCurrentExercise(of: activeProgram)
    }

    private func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            openSharedFile(at: url)
            return
        }
        guard url == RestActivityAttributes.currentExerciseURL else { return }
        openCurrentExercise()
    }

    private func openSharedFile(at url: URL) {
        TraceLog.record(.data, "Opened a shared file")
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            sharedImport = try SharedImport(file: SharedFile.decode(data), in: modelContext)
        } catch {
            sharedImportError = (error as? SharedFileError)?.errorDescription ?? SharedFileError.unreadable.errorDescription
        }
        // The system's copy in the app's Inbox is no longer needed.
        if url.path().contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A new template shows in Templates, in its own section.
    private func showImported(_ template: TemplateProgram?) {
        guard let template else { return }
        listedTemplateType = template.templateType
        selection = .templates
    }
}

#Preview("PowerJackRootView - Active Program") {
    let scenario = PowerJackSeed.weekOneProgress()

    PowerJackRootView()
        .modelContainer(scenario.container)
}

#Preview("PowerJackRootView - No Active Program") {
    PowerJackRootView()
        .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
