//
//  TemplateProgramListView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI
import TipKit

struct TemplateProgramListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSelect: ((TemplateProgram) -> Void)?

    @Query(
        filter: #Predicate<TemplateProgram> { !$0.hiddenValue },
        sort: \TemplateProgram.templateName
    ) private var templatePrograms: [TemplateProgram]
    @State private var selectedTemplate: TemplateProgram?
    @State private var templatePendingDelete: TemplateProgram?
    @State private var saveErrorMessage: String?

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
                emptySystemImage: "doc.on.doc",
                // Picking a template for a new program is no place for the intro.
                hint: onSelect == nil ? TemplatesHint() : nil
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
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // No destructive role: it removes the row before the user confirms.
                        Button {
                            templatePendingDelete = template
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            select(template)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .listRowSpacing(10)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemBackground))
            } createDestination: {
                TemplateProgramNew()
            }
            .navigationDestination(item: $selectedTemplate) { template in
                TemplateProgramDetailView(templateProgram: template)
            }
            .alert(
                "Delete “\(templatePendingDelete?.displayName ?? "")”?",
                isPresented: Binding(
                    get: { templatePendingDelete != nil },
                    set: { if !$0 { templatePendingDelete = nil } }
                ),
                presenting: templatePendingDelete
            ) { template in
                Button("Delete", role: .destructive) {
                    delete(template)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Programs you've already started from it won't change.")
            }
            .saveErrorAlert($saveErrorMessage)
        }
    }

    /// Picking a template for a program hides drafts, since they can't start one.
    private var visibleTemplates: [TemplateProgram] {
        guard onSelect != nil else { return templatePrograms }
        return templatePrograms.filter { !$0.draft }
    }

    private func delete(_ template: TemplateProgram) {
        template.delete()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "The template couldn't be deleted. Please try again."
        }
    }

    private func select(_ template: TemplateProgram) {
        guard let onSelect else {
            TemplatesHint().invalidate(reason: .actionPerformed)
            selectedTemplate = template
            return
        }

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
