//
//  PowerJackRootView.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

import SwiftData
import SwiftUI
import TipKit

enum MainBrowserOption: String {
    case programs = "Programs"
    case templates = "Templates"
    case volume = "Volume"
    case settings = "Settings"

    var symbol: String {
        switch self {
        case .programs: "dumbbell"
        case .templates: "square.stack.3d.up"
        case .volume: "chart.bar"
        case .settings: "gearshape"
        }
    }
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
        .onChange(of: selection) { _, selection in
            TraceLog.record(.screen, "Switched to \(selection.rawValue)")
        }
    }
}

private struct PowerJackScreens: View {
    @Binding var selection: MainBrowserOption
    @Binding var settingsPath: NavigationPath

    @Query private var programs: [Program]

    private var activeProgram: Program? { programs.active }

    private var showsWorkoutTabs: Bool {
        selection == .programs && idleControls.isOn
    }

    private var workoutTabInset: CGFloat { showsWorkoutTabs ? WorkoutTabBar.reservedHeight : 0 }

    @State private var router = ProgramsRouter()
    @State private var didRestore = false
    // Shared by the live workout and its tab bar.
    @State private var idleControls = IdleControls()

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
            Tab("Programs", systemImage: MainBrowserOption.programs.symbol, value: MainBrowserOption.programs) {
                NavigationStack(path: $router.path) {
                    ProgramListView()
                        .programRouteDestinations()
                }
                .powerJackTabPage(bottomInset: workoutTabInset)
                .toolbarVisibility(showsWorkoutTabs ? .hidden : .visible, for: .tabBar)
            }

            Tab("Templates", systemImage: MainBrowserOption.templates.symbol, value: MainBrowserOption.templates) {
                TemplateProgramListView()
                    .powerJackTabPage(bottomInset: workoutTabInset)
            }

            Tab("Volume", systemImage: MainBrowserOption.volume.symbol, value: MainBrowserOption.volume) {
                VolumeView()
                    .powerJackTabPage(bottomInset: workoutTabInset)
            }

            Tab("Settings", systemImage: MainBrowserOption.settings.symbol, value: MainBrowserOption.settings, role: settingsRole) {
                NavigationStack(path: $settingsPath) {
                    SettingsView()
                        .traceScreen("Settings")
                }
                .powerJackTabPage(bottomInset: workoutTabInset)
            }
        }
        .overlay(alignment: .bottom) {
            if showsWorkoutTabs {
                WorkoutTabBar(isCollapsed: idleControls.isTabBarCollapsed) { tab in
                    if tab == .programs {
                        if idleControls.isTabBarCollapsed {
                            idleControls.show()
                        } else {
                            router.popToRoot()
                        }
                    } else {
                        selection = tab
                    }
                }
            }
        }
        .restTimer(inWorkoutHeader: showsWorkoutHeader, onOpenCurrentExercise: openCurrentExercise)
        .environment(router)
        .environment(idleControls)
        .powerJackKeyboardBehavior()
        .revealsIdleControlsOnTap(idleControls)
        .onChange(of: selection) { _, section in
            switch section {
            case .programs: ProgramsHint.opened.sendDonation()
            case .templates: WelcomeHint().invalidate(reason: .actionPerformed)
            case .volume, .settings: break
            }
        }
        .onAppear(perform: restoreActiveWorkout)
        .onChange(of: router.path) { _, path in
            TraceLog.record(.screen, "Programs: \(path.isEmpty ? "My Programs" : path.map(\.traceName).joined(separator: " > "))")
        }
        .onOpenURL(perform: handleOpenURL)
    }

    /// On launch, and after an iCloud Backup switch, reopen the active program's current workout.
    private func restoreActiveWorkout() {
        guard !didRestore else { return }
        didRestore = true

        guard let activeProgram, activeProgram.nextWorkout != nil else { return }
        router.restore(activeProgram: activeProgram)
    }

    /// Takes the user to the exercise they should be doing, from the rest timer or its Live Activity.
    private func openCurrentExercise() {
        guard let activeProgram, activeProgram.nextWorkout != nil else { return }
        selection = .programs
        router.showCurrentExercise(of: activeProgram)
    }

    private func handleOpenURL(_ url: URL) {
        guard url == RestActivityAttributes.currentExerciseURL else { return }
        openCurrentExercise()
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
