//
//  ProgramDetailView.swift
//  PowerJack
//
//  Created on 6/28/26.
//

import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Bindable var program: Program

    @Environment(ProgramsRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.Key.developerTools) private var developerToolsEnabled = AppSettings.Default.developerTools
    @State private var isConfirmingProgressionUpdate = false
    @State private var saveErrorMessage: String?

    /// Each early workout gets its own hint on Start Workout, shown until it starts.
    private var startWorkoutHint: (any Hint)? {
        guard let workout = program.nextWorkout, workout.status == .planned,
              let occasion = HintOccasion(weekNumber: program.weekNumber(containing: workout), workout: workout)
        else {
            return nil
        }
        switch occasion {
        case .weekOneDayOne, .weekOneDayTwo:
            return BaselineHint(occasion: occasion, ratesRepsInReserve: program.templateType.ratesRepsInReserve)
        case .weekTwoDayOne: return SwapExerciseHint()
        case .weekTwoDayTwo: return RestSettingsHint()
        case .weekThreeDayOne: return EditExercisesHint()
        }
    }

    /// "Week 5 of 8 · 50%" while the program runs, otherwise its status.
    private var subtitle: String {
        if let workout = program.nextWorkout, let week = program.weekNumber(containing: workout) {
            return "Week \(week) of \(program.programLengthWeeks) · \(program.percentFinished)%"
        }
        return "\(program.status.rawValue.localizedCapitalized) · \(program.percentFinished)%"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                if let nextWorkout = program.nextWorkout {
                    ProgramUpNext(program: program, workout: nextWorkout, startHint: startWorkoutHint)
                } else {
                    EmptyStateView(
                        title: program.status == .complete ? "Program complete" : "No upcoming workouts",
                        systemImage: "checkmark.circle"
                    )
                }

                ProgramProgressGrid(program: program)
            }
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
            .padding(.bottom, LayoutMetrics.sectionSpacing)
        }
        .navigationTitle(program.templateName)
        .navigationSubtitle(subtitle)
        // Set here, not inherited, so a rebuild that opens straight onto this page keeps it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A finished program has no days ahead to edit.
            if program.nextWorkout != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let workout = program.nextWorkout, workout.status == .active {
                            Button(
                                workout.isPaused ? "Resume Workout" : "Pause Workout",
                                systemImage: workout.isPaused ? "play" : "pause"
                            ) {
                                togglePause(workout)
                            }
                        }
                        // Pushed through the router like every other Programs screen.
                        Button("Edit Days", systemImage: "square.and.pencil") {
                            router.showEditDays(program)
                        }
                        if developerToolsEnabled && program.canResetProgression {
                            Button("Force Update Progression", systemImage: "arrow.clockwise") {
                                isConfirmingProgressionUpdate = true
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
        .alert("Force Update Progression?", isPresented: $isConfirmingProgressionUpdate) {
            Button("Force Update", role: .destructive, action: forceUpdateProgression)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Workouts you haven't started this week get fresh sets, reps and weights from your ratings. Any changes you made to them will be replaced.")
        }
        .saveErrorAlert($saveErrorMessage)
    }

    /// A paused workout's clock stands still until Resume Workout or the next logged set.
    /// Pausing also ends the workout in Health and the Live Activity; resuming starts both again.
    private func togglePause(_ workout: Workout) {
        if workout.isPaused {
            workout.resume()
        } else {
            workout.pause()
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "The workout couldn't be paused or resumed. Please try again."
            return
        }
        // The Live Activity follows the workout on its own (see `activityState`).
        if workout.isPaused {
            WorkoutMirroring.shared.endWatchWorkout()
        } else {
            WorkoutMirroring.shared.openOnWatch()
        }
    }

    private func forceUpdateProgression() {
        program.resetProgression()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "Progression couldn't be updated. Please try again."
        }
    }
}

#Preview("ProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramDetailView(program: scenario.program)
    }
}
