//
//  TemplateListView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct TemplateListView: View {
    @Query(sort: \TemplateProgram.templateName) private var templatePrograms: [TemplateProgram]

    var body: some View {
        List {
            if templatePrograms.isEmpty {
                Text("No templates")
            } else {
                ForEach(templatePrograms, id: \.self) { templateProgram in
                    Text(templateProgram.templateName)
                }
            }
        }
    }
}

#Preview("TemplateListView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        TemplateListView()
    }
    .modelContainer(scenario.container)
}

#Preview("TemplateListView - Empty") {
    NavigationStack {
        TemplateListView()
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
