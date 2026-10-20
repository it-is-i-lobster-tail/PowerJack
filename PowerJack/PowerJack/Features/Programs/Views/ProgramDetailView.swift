//
//  ProgramDetailView.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Bindable var program: Program

    /// Each early workout gets its own hint on Start Workout, shown until it starts.
    private var startWorkoutHint: (any Hint)? {
        guard let workout = program.nextWorkout, workout.status == .planned,
              let occasion = HintOccasion(weekNumber: program.weekNumber(containing: workout), workout: workout)
        else {
            return nil
        }
        switch occasion {
        case .weekOneDayOne, .weekOneDayTwo: return BaselineHint(occasion: occasion)
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
    }
}

#Preview("ProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramDetailView(program: scenario.program)
    }
}
