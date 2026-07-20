//
//  TemplateProgramDetailView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct TemplateProgramDetailView: View {
    let templateProgram: TemplateProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(templateProgram.templateName)
                .font(.headline)
            Text("Workouts per week: \(templateProgram.workoutsPerWeek)")
            Text("Focus: \(focusText)")
        }
        .padding()
    }

    private var focusText: String {
        templateProgram.templateMuscleFocus.map(\.rawValue).joined(separator: ", ")
    }
}

#Preview("TemplateProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        TemplateProgramDetailView(templateProgram: scenario.templateProgram)
    }
    .modelContainer(scenario.container)
}
