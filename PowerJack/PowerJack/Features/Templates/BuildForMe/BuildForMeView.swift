//
//  BuildForMeView.swift
//  PowerJack
//
//  The Build for Me form: a few quick choices, each with a default, then Build. The template opens
//  for review unsaved; nothing is stored until the lifter saves it.
//

import SwiftData
import SwiftUI

struct BuildForMeView: View {
    private enum Phase: Equatable {
        case choosing
        case building
        case notEnoughEquipment(String)
    }

    /// Called once the reviewed template is saved, to leave the flow.
    let onSave: () -> Void

    @Query private var exercises: [Exercise]
    @AppStorage(EquipmentChoice.storageKey) private var storedEquipment = ""

    @State private var choices: BuildForMeChoices
    @State private var phase = Phase.choosing
    @State private var buildTask: Task<Void, Never>?
    @State private var review: TemplateProgramDraft?

    private let boxHeight: CGFloat = 85
    private let workoutsPerWeekOptions = Array(
        TemplateProgramDraft.minimumWorkoutsPerWeek...TemplateProgramDraft.maximumWorkoutsPerWeek
    )

    init(type: TemplateType, onSave: @escaping () -> Void) {
        self.onSave = onSave
        var choices = BuildForMeChoices(type: type)
        choices.equipment = EquipmentChoice(stored: UserDefaults.standard.string(forKey: EquipmentChoice.storageKey) ?? "")
        _choices = State(initialValue: choices)
    }

    var body: some View {
        content.traceScreen("Build for Me")
    }

    private var content: some View {
        GlassFormScaffold(
            navigationTitle: "Build for Me",
            headerSystemImage: "wand.and.sparkles",
            headerTitle: "Pick a few things and get a full template to review"
        ) {
            picker("Type", systemImage: "chart.line.uptrend.xyaxis", detail: "How it progresses",
                   selection: $choices.type, options: TemplateType.allCases) { Text($0.name) }

            picker("Workouts per Week", systemImage: "calendar.badge.clock", detail: "Choose two to six workout days",
                   selection: $choices.workoutsPerWeek, options: workoutsPerWeekOptions) { Text($0, format: .number) }

            TemplateFocusSelectionLink(
                boxHeight: boxHeight,
                detail: "Optional, up to four",
                selectedMuscles: $choices.focus
            )

            EquipmentChips(choice: $choices.equipment)

            picker("Session Length", systemImage: "timer", detail: "Sets exercises per day",
                   selection: $choices.sessionMinutes, options: TemplateRequest.sessionLengths) { Text("\($0) min") }

            picker("Lean Toward", systemImage: "scalemass", detail: "Which kind of exercise comes first",
                   selection: $choices.lean, options: TemplateRequest.Lean.allCases) { Text($0.name) }

            Toggle(isOn: $choices.supersets) {
                FormFieldLabel(systemImage: "link", title: "Supersets", detail: "Pair small lifts to save time")
            }
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
            .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
            .powerJackGlassCard(interactive: true)

            if case .notEnoughEquipment(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            if phase == .building {
                HStack {
                    ProgressView()
                    Text("Building…")
                    Spacer()
                    Button("Cancel", action: cancel)
                }
                .padding(.vertical, 10)
            } else {
                FormSubmitButton(title: "Build", isEnabled: true, action: build)
            }
        }
        .onChange(of: choices) { _, newValue in
            storedEquipment = newValue.equipment.stored
            // A change might fix what the message names, so it waits for the next Build.
            if case .notEnoughEquipment = phase { phase = .choosing }
        }
        .navigationDestination(isPresented: isReviewing) {
            if let review {
                BuildForMeReview(draft: review, onSave: onSave)
            }
        }
    }

    private var isReviewing: Binding<Bool> {
        Binding(get: { review != nil }, set: { if !$0 { review = nil } })
    }

    private func picker<Option: Hashable, OptionLabel: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        detail: LocalizedStringKey,
        selection: Binding<Option>,
        options: [Option],
        @ViewBuilder optionLabel: @escaping (Option) -> OptionLabel
    ) -> some View {
        // The field picks from an optional; every choice here always has a value.
        let optional = Binding<Option?>(get: { selection.wrappedValue }, set: { $0.map { selection.wrappedValue = $0 } })
        return GlassPickerField(selection: optional, options: options, height: boxHeight) {
            FormFieldLabel(systemImage: systemImage, title: title, detail: detail)
        } optionLabel: { option in
            optionLabel(option)
        }
    }

    private func build() {
        phase = .building
        let choices = choices
        let exercises = Self.inBuildOrder(exercises)
        let snapshot = exercises.map { BuilderExercise($0, uses: ($0.workoutExercisesValue ?? []).count) }
        buildTask = Task {
            // Lets the progress row show before the build runs.
            await Task.yield()
            let outcome = BuildForMeOutcome(choices, exercises: snapshot)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .plan(let plan):
                phase = .choosing
                review = plan.makeDraft(for: choices.request, exercises: exercises)
            case .notEnoughEquipment(let message):
                phase = .notEnoughEquipment(message)
            }
        }
    }

    /// Built-ins in catalog order, then the lifter's own by name. The builder breaks ties by this
    /// order, and a fetch comes back in no fixed order, so the same choices always build the same template.
    static func inBuildOrder(_ exercises: [Exercise]) -> [Exercise] {
        let catalogOrder = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.enumerated().map { ($1.id, $0) })
        return exercises.sorted { first, second in
            let firstRank = first.catalogID.flatMap { catalogOrder[$0] } ?? Int.max
            let secondRank = second.catalogID.flatMap { catalogOrder[$0] } ?? Int.max
            return firstRank != secondRank ? firstRank < secondRank : first.exerciseName < second.exerciseName
        }
    }

    private func cancel() {
        buildTask?.cancel()
        buildTask = nil
        phase = .choosing
    }
}

extension TemplateRequest.Lean {
    var name: String {
        switch self {
        case .freeWeights: "Free Weights"
        case .mix: "Mix"
        case .machines: "Machines and Cables"
        }
    }
}

#Preview("Build for Me") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.exercises().container) {
        BuildForMeView(type: .hypertrophy, onSave: {})
    }
}
