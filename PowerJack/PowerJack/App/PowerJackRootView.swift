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
    // A new ID rebuilds the Templates tab, which returns it to its list.
    @State private var templatesRootID = UUID()
    // Measured height of the floating bar, reserved at the bottom of every tab.
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        // Standard tabs can't be swiped between, so only the picker below switches sections.
        TabView(selection: $selection) {
            Tab(value: MainBrowserOption.programs) {
                // Programs gets its own navigation world.
                NavigationStack(path: $router.path) {
                    ProgramListView()
                        .programRouteDestinations()
                }
                .toolbar(.hidden, for: .tabBar)
                .powerJackTabPage(bottomBarHeight: bottomBarHeight)
            }

            Tab(value: MainBrowserOption.templates) {
                TemplateProgramListView()
                    .id(templatesRootID)
                    .toolbar(.hidden, for: .tabBar)
                    .powerJackTabPage(bottomBarHeight: bottomBarHeight)
            }
        }
        // Tab pages don't inherit a safe-area inset set on the TabView,
        // so the bar floats here and each tab page stops short of it.
        .overlay(alignment: .bottom) {
            GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
                // The switcher stays centered on screen; the gear sits apart at the leading edge.
                SlidingGlassPicker(
                    options: MainBrowserOption.allCases,
                    selection: $selection,
                    title: \.name,
                    onTap: showList
                )
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    SettingsButton { isShowingSettings = true }
                }
                .padding(.horizontal)
            }
            // A little breathing room between screen content and the bar.
            .padding(.top, LayoutMetrics.compactSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                bottomBarHeight = height
            }
        }
        .restTimer(onOpenCurrentExercise: openCurrentExercise)
        .environment(router)
        .powerJackKeyboardBehavior()
        .onAppear(perform: restoreActiveWorkout)
        .onOpenURL(perform: handleOpenURL)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }

    /// Tapping a section always lands on its list, like a tab bar.
    private func showList(of option: MainBrowserOption) {
        switch option {
        case .programs:
            router.popToRoot()
        case .templates:
            templatesRootID = UUID()
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
    // Matches the switcher's height: a 44pt pill plus its 4pt padding.
    private static let size: CGFloat = 52

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
