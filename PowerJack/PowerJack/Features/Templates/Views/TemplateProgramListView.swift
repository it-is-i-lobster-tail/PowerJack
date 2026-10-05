//
//  TemplateProgramListView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct TemplateProgramListView: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: ((TemplateProgram) -> Void)?

    @Query(sort: \TemplateProgram.templateName) private var templatePrograms: [TemplateProgram]
    @State private var selectedTemplate: TemplateProgram?

    init(
        onSelect: ((TemplateProgram) -> Void)? = nil
    ) {
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            AddableListScaffold(
                navigationTitle: "My Templates",
                isEmpty: visibleTemplates.isEmpty,
                emptyTitle: "No templates",
                emptySystemImage: "doc.on.doc"
            ) {
                List(visibleTemplates) { template in
                    Button {
                        select(template)
                    } label: {
                        VStack {
                            HStack {
                                Text(template.displayName)
                                Spacer()
                            }

                            TemplateProgramInfo(
                                templateMuscleFocus: template.templateMuscleFocus,
                                workoutsPerWeek: template.workoutsPerWeek
                            )
                        }
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            select(template)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemBackground))
            } createDestination: {
                 TemplateProgramNew(
                    onSave: handleNewTemplate
                 )
            }
            .navigationDestination(item: $selectedTemplate) { template in
                TemplateProgramDetailView(templateProgram: template)
            }
        }
    }

    /// Picking a template for a program hides drafts, since they can't start one.
    private var visibleTemplates: [TemplateProgram] {
        guard onSelect != nil else { return templatePrograms }
        return templatePrograms.filter { !$0.draft }
    }

    private func select(_ template: TemplateProgram) {
        guard let onSelect else {
            selectedTemplate = template
            return
        }

        onSelect(template)
        dismiss()
    }

    private func handleNewTemplate(_ template: TemplateProgram) {
        guard let onSelect, !template.draft else { return }
        onSelect(template)
        dismiss()
    }
}

#Preview("TemplateListView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    TemplateProgramListView()
        .modelContainer(scenario.container)
}

#Preview("TemplateListView - Empty") {
    TemplateProgramListView()
        .modelContainer(PowerJackSeed.makeInMemoryContainer())
}

private struct TemplateProgramInfo: View {
    let templateMuscleFocus: [Muscle]
    let workoutsPerWeek: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("\(workoutsPerWeek) days/wk")
                .font(.caption2)

            Text("|")
                .font(.caption2)
                .padding(.horizontal, 2)

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
