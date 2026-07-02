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
            
            let programInfoBannerVerticalAlloction = 0.1
            let programFocusInfoVerticalAlloction = 0.15
            let programStartWorkoutVerticalAlloction = 0.085
            let programFooterControlsVerticalAlloction = 0.05
            let programBottomBuffer = 0.025
            let programDetailBuffer = 0.01
            let countDetialBuffers: Double = 4.0
            //
            let programProgressGridVerticalAlloction = 1 - programInfoBannerVerticalAlloction - programFooterControlsVerticalAlloction - programFocusInfoVerticalAlloction - programStartWorkoutVerticalAlloction - (programDetailBuffer * countDetialBuffers) - programDetailBuffer - 0.001
            
            VStack(spacing: 0) {
                // Info Banner
                ProgramInfoBanner(
                    program: program
                )
                    .frame(width: screenWidth, height: screenHeight * programInfoBannerVerticalAlloction)
                // Divider Line
                Color.gray.opacity(0.8)
                    .frame(width: screenWidth * 0.9, height: screenHeight * 0.001)
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
                    workableHeight: screenHeight * programProgressGridVerticalAlloction,
                    program: program
                )
                .frame(width: screenWidth, height: screenHeight * programProgressGridVerticalAlloction)
                
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
                           height: screenHeight * programFocusInfoVerticalAlloction)
                // Detail Buffer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programDetailBuffer
                    )
                // Start/Resume Program
                ProgramStartWorkout(
                    screenWidth: screenWidth * 0.9,
                    hight: screenHeight * programStartWorkoutVerticalAlloction * 0.95
                )
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programStartWorkoutVerticalAlloction
                    )
                // Detail Buffer
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: screenWidth,
                        height: screenHeight * programDetailBuffer
                    )
                // Footer Controls
                ProgramFooterControls()
                    .frame(width: screenWidth, height: screenHeight * programFooterControlsVerticalAlloction)
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

#Preview ("ProgramDetailView"){
    ProgramDetailView(program: PreviewProgram.programPreview)
        .modelContainer(makeWorkoutPreviewContainer())
}
