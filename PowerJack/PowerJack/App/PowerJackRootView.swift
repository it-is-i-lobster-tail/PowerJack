//
//  PowerJackRootView.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

import SwiftData
import SwiftUI

private enum MainBrowserOption:
    CaseIterable,
    Hashable,
    Identifiable
{
    case programs
    case templates

    var id: Self { self }

    var name: String {
        switch self {
        case .programs:
            "Programs"
        case .templates:
            "Templates"
        }
    }
}

struct PowerJackRootView: View {
    @Query private var programs: [Program]

    private var activeProgram: Program? { programs.active }
    @State private var options: [MainBrowserOption] = [
        MainBrowserOption.programs,
        MainBrowserOption.templates
    ]
    @State private var selection: MainBrowserOption = MainBrowserOption.programs
    @State private var router = ProgramsRouter()
    @State private var didRestore = false
    @State private var isShowingSettings = false

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: MainBrowserOption.programs) {
                // Programs gets its own navigation world.
                NavigationStack(path: $router.path) {
                    ProgramListView()
                        .programRouteDestinations()
                }
            }

            Tab(value: MainBrowserOption.templates) {
                TemplateProgramListView()
            }
        }
        // Turns the tabs into horizontally swipeable pages.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
                HStack(spacing: LayoutMetrics.compactSpacing) {
                    SettingsButton { isShowingSettings = true }

                    SlidingGlassPicker(
                        options: MainBrowserOption.allCases,
                        selection: $selection,
                        title: \.name
                    )
                }
            }
        }
        .restTimer(onOpenCurrentExercise: openCurrentExercise)
        .environment(router)
        .onAppear(perform: restoreActiveWorkout)
        .onOpenURL(perform: handleOpenURL)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }

    /// On launch, reopen the active program's current workout.
    private func restoreActiveWorkout() {
        guard !didRestore else { return }
        didRestore = true

        guard let activeProgram, activeProgram.nextWorkout != nil else { return }
        selection = .programs
        router.restore(activeProgram: activeProgram)
    }

    /// Takes the user to the exercise they should be doing, from the rest timer or its Live Activity.
    private func openCurrentExercise() {
        guard let activeProgram, activeProgram.nextWorkout != nil else { return }
        isShowingSettings = false
        selection = .programs
        router.showCurrentExercise(of: activeProgram)
    }

    private func handleOpenURL(_ url: URL) {
        guard url == RestActivityAttributes.currentExerciseURL else { return }
        openCurrentExercise()
    }
}

private struct SettingsButton: View {
    private static let size: CGFloat = 46

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.title3)
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .powerJackGlassCircle(interactive: true)
        .accessibilityLabel("Settings")
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
