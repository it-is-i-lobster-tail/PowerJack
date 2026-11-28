//
//  TemplateProgramListView.swift
//  PowerJack
//
//  Created on 7/3/26.
//

import SwiftData
import SwiftUI
import TipKit

struct TemplateProgramListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The two ways to add a template, from the + menu.
    enum Creation {
        case newTemplate, buildForMe
    }

    let onSelect: ((TemplateProgram) -> Void)?

    @Query(
        filter: #Predicate<TemplateProgram> { !$0.hiddenValue },
        sort: \TemplateProgram.templateName
    ) private var templatePrograms: [TemplateProgram]
    // Remembered so returning to Templates keeps the section the lifter was in.
    @AppStorage(TemplateType.selectionKey) private var templateType: TemplateType = .hypertrophy
    @State private var selectedTemplate: TemplateProgram?
    @State private var templatePendingDelete: TemplateProgram?
    @State private var saveErrorMessage: String?
    @State private var creation: Creation?

    /// `creation` opens one of the + menu's screens right away, for tests: hosted menus don't take taps.
    init(
        onSelect: ((TemplateProgram) -> Void)? = nil,
        creation: Creation? = nil
    ) {
        self.onSelect = onSelect
        _creation = State(initialValue: creation)
    }

    var body: some View {
        content.traceScreen("Templates")
    }

    @ViewBuilder
    private var content: some View {
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
            } addMenu: {
                Button("New Template", systemImage: "square.and.pencil") { creation = .newTemplate }
                Button("Build for Me", systemImage: "wand.and.sparkles") { creation = .buildForMe }
            }
            .navigationDestination(isPresented: isCreating(.newTemplate)) {
                TemplateProgramNew(templateType: templateType)
            }
            .navigationDestination(isPresented: isCreating(.buildForMe)) {
                BuildForMeView(type: templateType) { creation = nil }
            }
            // Outside the scaffold, so the switcher sits above its hint.
            .safeAreaBar(edge: .top, spacing: 0) {
                Picker("Template type", selection: $templateType) {
                    ForEach(TemplateType.allCases) { type in
                        Text(type.name).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, LayoutMetrics.compactSpacing)
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
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func isCreating(_ kind: Creation) -> Binding<Bool> {
        Binding(get: { creation == kind }, set: { if !$0 { creation = nil } })
    }

    /// The chosen section's templates. Picking one for a program hides drafts, since they can't start one.
    private var visibleTemplates: [TemplateProgram] {
        templatePrograms.filter { template in
            template.templateType == templateType && (onSelect == nil || !template.draft)
        }
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

            // A draft can have no focus muscles yet, so nothing follows the divider.
            if !templateMuscleFocus.isEmpty {
                Text("|")
                    .font(.caption2)
                    .padding(.horizontal, 2)
            }

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
