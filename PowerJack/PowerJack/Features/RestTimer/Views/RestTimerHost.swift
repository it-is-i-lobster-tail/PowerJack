//
//  RestTimerHost.swift
//  PowerJack
//
//  Shows the active workout's rest in the in-app island and keeps the Live Activity on its current set.
//

import SwiftData
import SwiftUI
import TipKit

extension View {
    /// Adds the rest timer for the active program's current workout.
    func restTimer(onOpenCurrentExercise: @escaping () -> Void) -> some View {
        modifier(RestTimerHost(onOpenCurrentExercise: onOpenCurrentExercise))
    }
}

private struct RestTimerHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var programs: [Program]

    @AppStorage(AppSettings.Key.inAppRestTimer)
    private var showsInAppTimer = AppSettings.Default.inAppRestTimer
    @AppStorage(AppSettings.Key.restLiveActivity)
    private var showsLiveActivity = AppSettings.Default.restLiveActivity

    @State private var isExpanded = false
    /// Refreshed when a rest starts and when its "Start set" window runs out.
    @State private var clock = Date.now

    let onOpenCurrentExercise: () -> Void

    private var activeProgram: Program? { programs.active }
    private var workout: Workout? { activeProgram?.nextWorkout }
    private var rest: RestPeriod? { workout?.currentRest }

    private var restTimerHint: RestTimerHint? {
        guard let activeProgram, let workout,
              let occasion = HintOccasion(weekNumber: activeProgram.weekNumber(containing: workout), workout: workout)
        else {
            return nil
        }
        return RestTimerHint(occasion: occasion)
    }

    private var islandRest: RestPeriod? {
        guard showsInAppTimer, let rest, !rest.isExpired(at: clock) else { return nil }
        return rest
    }

    private var workoutTitle: String? {
        guard let activeProgram, let workout else { return nil }
        return activeProgram.activityTitle(for: workout)
    }

    private var liveActivityInput: LiveActivityInput {
        LiveActivityInput(
            state: workout?.activityState(),
            workoutTitle: workoutTitle,
            isEnabled: showsLiveActivity,
            isAppActive: scenePhase == .active
        )
    }

    func body(content: Content) -> some View {
        content
            // Keeps the collapsed island from covering navigation bars.
            .safeAreaInset(edge: .top, spacing: 0) {
                if islandRest != nil {
                    Color.clear.frame(height: RestIsland.reservedHeight)
                }
            }
            .overlay {
                if isExpanded {
                    Color.black.opacity(VisualOpacity.subtle)
                        .ignoresSafeArea()
                        .onTapGesture(perform: collapse)
                        .transition(.opacity)
                }
            }
            // The expanded island draws over the content instead of pushing it down.
            .overlay(alignment: .top) {
                if let islandRest {
                    RestIsland(
                        rest: islandRest,
                        isExpanded: $isExpanded,
                        onOpenExercise: onOpenCurrentExercise
                    )
                    .popoverHint(restTimerHint)
                    .padding(.top, 4)
                    .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.2), value: islandRest != nil)
            .onChange(of: islandRest == nil) { _, isHidden in
                if isHidden { isExpanded = false }
            }
            // Tapping the island is the hint's whole lesson, so it's done after that.
            .onChange(of: isExpanded) { _, expanded in
                if expanded { restTimerHint?.invalidate(reason: .actionPerformed) }
            }
            .task(id: rest) { await refreshClock(for: rest) }
            .task(id: liveActivityInput) { await syncLiveActivity(liveActivityInput) }
    }

    private func collapse() {
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            isExpanded = false
        }
    }

    /// Hides the island once "Start set" has been up for its whole window.
    private func refreshClock(for rest: RestPeriod?) async {
        clock = .now
        guard let rest, !rest.isExpired(at: clock) else { return }
        try? await Task.sleep(for: .seconds(rest.expiresAt.timeIntervalSinceNow))
        guard !Task.isCancelled else { return }
        withAnimation { clock = .now }
    }

    private func syncLiveActivity(_ input: LiveActivityInput) async {
        await RestLiveActivityController.sync(
            state: input.state,
            workoutTitle: input.workoutTitle,
            isEnabled: input.isEnabled
        )
    }
}

/// Everything the Live Activity depends on. Coming back to the foreground re-syncs it,
/// which retries a start that failed in the background.
private struct LiveActivityInput: Equatable {
    let state: WorkoutActivityState?
    let workoutTitle: String?
    let isEnabled: Bool
    let isAppActive: Bool
}
