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
                    focusMuscles: program.templateProgram.templateMuscleFocus,
                    screenWidth: screenWidth * 0.9
                )
                .frame(width: screenWidth * 0.9,
                           height: screenHeight * programFocusInfoVerticalAllocation)
                // Detail Buffer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programDetailBuffer
                    )
                Group {
                    if let nextWorkout = program.nextWorkout {
                        ProgramStartWorkout(
                            screenWidth: screenWidth * 0.9,
                            height: screenHeight * programStartWorkoutVerticalAllocation * 0.95,
                            workout: nextWorkout
                        )
                    } else {
                        EmptyStateView(
                            title: "No upcoming workouts",
                            systemImage: "checkmark.circle"
                        )
                    }
                }
                .frame(
                    width: screenWidth,
                    height: screenHeight * programStartWorkoutVerticalAllocation
                )
                // Detail Buffer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programDetailBuffer
                    )
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programBottomBuffer
                    )
            }
        }
    }
}

#Preview("ProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ProgramDetailView(program: scenario.program)
    }
        .modelContainer(scenario.container)
}
