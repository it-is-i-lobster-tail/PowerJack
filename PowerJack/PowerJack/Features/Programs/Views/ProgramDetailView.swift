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

    /// Each early workout gets its own hint above Start Workout, shown until it starts.
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

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            let programInfoBannerVerticalAllocation = 0.1
            let programFocusInfoVerticalAllocation = 0.15
            let programStartWorkoutVerticalAllocation = 0.085
            let programBottomBuffer = 0.025
            let programDetailBuffer = 0.01
            let detailBufferCount = 4.0
            let programDividerVerticalAllocation = 0.001
            let programProgressGridVerticalAllocation = 1
                - programInfoBannerVerticalAllocation
                - programFocusInfoVerticalAllocation
                - programStartWorkoutVerticalAllocation
                - (programDetailBuffer * detailBufferCount)
                - programBottomBuffer
                - programDividerVerticalAllocation
                - 0.025

            VStack(spacing: 0) {
                // Info Banner
                ProgramInfoBanner(
                    program: program
                )
                    .frame(width: screenWidth, height: screenHeight * programInfoBannerVerticalAllocation)
                // Divider Line
                Color.gray.opacity(0.8)
                    .frame(
                        width: screenWidth * 0.9,
                        height: screenHeight * programDividerVerticalAllocation
                    )
                // Detail Buffer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programDetailBuffer
                    )
                // Progression Grid
                ProgramProgressGrid(
                    workableWidth: screenWidth * 0.8875,
                    workableHeight: screenHeight * programProgressGridVerticalAllocation,
                    program: program
                )
                .frame(width: screenWidth, height: screenHeight * programProgressGridVerticalAllocation)

                // Detail Buffer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programDetailBuffer
                    )
                // Focus Info
                ProgramFocusInfo(
                    focusMuscles: program.templateMuscleFocus,
                    screenWidth: screenWidth * 0.9
                )
                .frame(width: screenWidth * 0.9,
                           height: screenHeight * programFocusInfoVerticalAllocation)
                Spacer()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if let nextWorkout = program.nextWorkout {
                        ProgramStartWorkout(
                            screenWidth: screenWidth * 0.9,
                            height: screenHeight
                                * programStartWorkoutVerticalAllocation
                                * 0.95,
                            program: program,
                            workout: nextWorkout
                        )
                        .popoverHint(startWorkoutHint, arrowEdge: .bottom)
                    } else {
                        EmptyStateView(
                            title: "No upcoming workouts",
                            systemImage: "checkmark.circle"
                        )
                        .frame(
                            maxWidth: screenWidth * 0.9,
                            minHeight: screenHeight
                                * programStartWorkoutVerticalAllocation
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, screenHeight * programBottomBuffer)
            }
        }
    }
}

#Preview("ProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramDetailView(program: scenario.program)
    }
}
