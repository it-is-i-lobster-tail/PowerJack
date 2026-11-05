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
    @State private var isConfirmingReset = false
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
                        // Pushed through the router like every other Programs screen.
                        Button("Edit Days", systemImage: "square.and.pencil") {
                            router.showEditDays(program)
                        }
                        if program.canResetProgression {
                            Button("Reset Progression", systemImage: "arrow.counterclockwise") {
                                isConfirmingReset = true
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
        .alert("Reset Progression?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive, action: resetProgression)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reruns the progression system to determine reps, sets, and weight for any workouts this week not started. This is a development tool and in most cases will change nothing.")
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private func resetProgression() {
        program.resetProgression()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "Progression couldn't be reset. Please try again."
        }
    }
}

#Preview("ProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramDetailView(program: scenario.program)
    }
}
