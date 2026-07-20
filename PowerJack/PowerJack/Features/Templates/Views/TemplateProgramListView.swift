//
//  TemplateProgramListView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct TemplateProgramListView: View {
    @Query(sort: \TemplateProgram.templateName) private var templatePrograms: [TemplateProgram]

    @State private var selectedTemplate: TemplateProgram?

    var body: some View {
        AddableListScaffold(
            navigationTitle: "My Templates",
            isEmpty: templatePrograms.isEmpty,
            emptyTitle: "No templates",
            emptySystemImage: "doc.on.doc"
        ) {
            List(templatePrograms) { template in
                Button {
                    select(template)
                } label: {
                    VStack {
                        HStack {
                            Text(template.templateName)
                            Spacer()
                        }

                        TemplateProgramFocusMusclesView(
                            templateMuscleFocus: template.templateMuscleFocus
                        )
                    }
                }
            }
        } createDestination: {
            TemplateProgramNew(onSave: handleNewTemplate)
        }
        .navigationDestination(item: $selectedTemplate) { template in
            TemplateProgramDetailView(templateProgram: template)
        }
    }

    private func select(_ template: TemplateProgram) {
        selectedTemplate = template
    }

    private func handleNewTemplate(_: TemplateProgram) {}
}

#Preview("TemplateListView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        TemplateProgramListView()
    }
    .modelContainer(scenario.container)
}

#Preview("TemplateListView - Empty") {
    NavigationStack {
        TemplateProgramListView()
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}

private struct TemplateProgramFocusMusclesView: View {
    let templateMuscleFocus: [Muscle]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(templateMuscleFocus.enumerated()), id: \.element.id) { index, muscleFocus in
                Text(muscleFocus.rawValue.localizedCapitalized)
                    .font(.caption2)

                if index < templateMuscleFocus.count - 1 {
                    Text("*")
                        .font(.caption2)
                }
            }
            Spacer()
        }
        .padding(.top, 0.1)
    }
}
