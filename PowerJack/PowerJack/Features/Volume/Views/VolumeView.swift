//
//  VolumeView.swift
//  PowerJack
//
//  The user's training history: average working sets per week for every muscle,
//  colored by what that volume means for growth.
//

import SwiftData
import SwiftUI

struct VolumeView: View {
    @Query private var logs: [WorkoutLog]
    @State private var range: VolumeRange = .days30

    private var bars: [MuscleBar] {
        let averages = WeeklyVolume.averages(of: logs, in: range)
        return Muscle.allCases.map { muscle in
            let sets = averages[muscle] ?? 0
            let tier = VolumeTier(weeklySets: sets)
            return MuscleBar(muscle: muscle, value: sets, color: tier.color, accessibilityNote: tier.name)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    EmptyStateView(
                        title: "No workouts yet",
                        systemImage: "chart.bar",
                        description: "Finish a workout to see your weekly volume."
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Volume")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Picker("Range", selection: $range) {
                    ForEach(VolumeRange.allCases) { range in
                        Text(range.name).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Text("Average working sets per week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                MuscleBarChart(bars: bars, fractionDigits: 1, spokenUnit: "sets per week")

                VolumeLegend()
                    .padding(.top, LayoutMetrics.compactSpacing)
            }
            .padding(.horizontal)
            .padding(.bottom, LayoutMetrics.sectionSpacing)
        }
    }
}

/// What each bar color means.
private struct VolumeLegend: View {
    private static let swatchSize: CGFloat = 12

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: 6) {
            ForEach(VolumeTier.allCases) { tier in
                GridRow {
                    Circle()
                        .fill(tier.color)
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                    Text(tier.name)
                    Text("\(tier.setRange) sets")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.subheadline)
    }
}

#Preview("VolumeView - Empty") {
    VolumeView()
        .modelContainer(PowerJackSeed.makeInMemoryContainer())
}

#Preview("VolumeView - History") {
    let container = PowerJackSeed.makeInMemoryContainer()
    for daysAgo in stride(from: 1, through: 28, by: 2) {
        container.mainContext.insert(WorkoutLog(
            date: .now.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60),
            setsByMuscle: [.chest: 4, .back: 3, .shoulders: 2, .triceps: 2, .biceps: 1.5, .quads: 6, .calves: 0.5]
        ))
    }

    return VolumeView()
        .modelContainer(container)
}
