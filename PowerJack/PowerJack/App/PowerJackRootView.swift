//
//  PowerJackRootView.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

import SwiftData
import SwiftUI
import TipKit

private enum MainBrowserOption:
    CaseIterable,
    Hashable,
    Identifiable
{
    case programs
    case templates
    case volume

    var id: Self { self }

    var name: String {
        switch self {
        case .programs:
            "Programs"
        case .templates:
            "Templates"
        case .volume:
            "Volume"
        }
    }
}

struct PowerJackRootView: View {
    @Environment(\.modelContext) private var modelContext
    // Missing in previews, which never switch iCloud Backup.
    @Environment(PowerJackStore.self) private var store: PowerJackStore?

    // Kept out here so they survive the rebuild below.
    @State private var selection: MainBrowserOption = MainBrowserOption.programs
    @State private var isShowingSettings = false
    // After a switch from Settings, the screens rebuild once Settings closes, so nothing
    // from them (like a hint popover) shows up on top of it.
    @State private var rebuildsAfterSettings = false

    private var showsScreens: Bool {
        store?.isReplacingContainer != true && !rebuildsAfterSettings
    }

    var body: some View {
        Group {
            // Switching iCloud Backup replaces the container. The screens holding its models
            // come down first, then the new container opens and they rebuild from it.
            // Settings and the chosen section stay put.
            if showsScreens {
                PowerJackScreens(selection: $selection, isShowingSettings: $isShowingSettings)
                    .id(ObjectIdentifier(modelContext.container))
            } else {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .onChange(of: store?.isReplacingContainer, initial: true) { _, isReplacing in
                        guard isReplacing == true else { return }
                        rebuildsAfterSettings = isShowingSettings
                        store?.replaceContainer()
                    }
            }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: { rebuildsAfterSettings = false }) {
            SettingsView()
                .traceScreen("Settings")
        }
        .onChange(of: selection) { _, selection in
            TraceLog.record(.screen, "Switched to \(selection.name)")
        }
    }
}

private struct PowerJackScreens: View {
    @Binding var selection: MainBrowserOption
    @Binding var isShowingSettings: Bool

    @Query private var programs: [Program]

    private var activeProgram: Program? { programs.active }

    /// Welcomes a new lifter toward Templates.
    private var welcomeHint: WelcomeHint? {
        programs.isEmpty ? WelcomeHint() : nil
    }

    @State private var router = ProgramsRouter()
    @State private var didRestore = false
    // A new ID rebuilds the Templates tab, which returns it to its list.
    @State private var templatesRootID = UUID()
    // Measured height of the floating bar, added to the safe area of every tab.
    @State private var bottomBarHeight: CGFloat = 0
    // How far in the navigation bar puts its buttons, so the bottom bar can line up with them.
    @State private var barButtonInset: CGFloat = 16
    // A workout fades the bars away while it sits idle.
    @State private var idleControls = IdleControls()

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

            Tab(value: MainBrowserOption.volume) {
                VolumeView()
                    .toolbar(.hidden, for: .tabBar)
                    .powerJackTabPage(bottomBarHeight: bottomBarHeight)
            }
        }
        // The bar floats over the tabs. Each tab page makes room for it in its safe area,
        // so content scrolls under the glass but comes to rest above it.
        .overlay(alignment: .bottom) {
            GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
                // The gear sits beside the switcher, apart enough that their glass doesn't merge.
                HStack(spacing: LayoutMetrics.compactSpacing * 1.5) {
                    SettingsButton { isShowingSettings = true }

                    SlidingGlassPicker(
                        options: MainBrowserOption.allCases,
                        selection: $selection,
                        title: \.name,
                        onTap: showList,
                        fillsWidth: true
                    )
                }
                // The gear sits right under the back button, and the switcher ends under the top bar's trailing buttons.
                .padding(.leading, barButtonInset + (LayoutMetrics.barButtonSize - SettingsButton.size) / 2)
                .padding(.trailing, barButtonInset)
            }
            // Popovers can't present from inside the glass container, so they attach out here.
            .popoverHints(["templates": welcomeHint], arrowEdge: .bottom)
            // A little breathing room between screen content and the bar.
            .padding(.top, LayoutMetrics.compactSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                bottomBarHeight = height
            }
            .fadesWhenIdle(idleControls)
        }
        .restTimer(onOpenCurrentExercise: openCurrentExercise)
        .environment(router)
        .environment(idleControls)
        .powerJackKeyboardBehavior()
        .revealsIdleControlsOnTap(idleControls)
        .onBarButtonInsetChange { barButtonInset = $0 }
        .onAppear(perform: restoreActiveWorkout)
        .onChange(of: router.path) { _, path in
            TraceLog.record(.screen, "Programs: \(path.isEmpty ? "My Programs" : path.map(\.traceName).joined(separator: " > "))")
        }
        .onOpenURL(perform: handleOpenURL)
    }

    /// Tapping a section always lands on its list, like a tab bar.
    private func showList(of option: MainBrowserOption) {
        switch option {
        case .programs:
            ProgramsHint.opened.sendDonation()
            router.popToRoot()
        case .templates:
            WelcomeHint().invalidate(reason: .actionPerformed)
            templatesRootID = UUID()
        case .volume:
            break
        }
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
    static let size: CGFloat = 52

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
