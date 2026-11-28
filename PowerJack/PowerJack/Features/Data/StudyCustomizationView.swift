import SwiftUI

struct StudyCustomizationView: View {
    let id: TrainingStudy
    let history: StudyHistory
    let apply: (StudyOptions) -> Void
    @State var draft: StudyOptions
    @State private var detent: PresentationDetent = .large
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let source = history.result(for: id, options: draft)
        let preview = source.presented(as: draft.presentation, transpose: draft.transpose)
        return NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        StudyFigureView(study: preview, compact: true)
                            .frame(width: 76, height: 46).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.displayTitle).font(.headline)
                            Text(source.figure == nil ? "No matching history" : source.scope)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Display") {
                    Picker("Chart type", selection: $draft.presentation) {
                        ForEach(source.availablePresentations, id: \.self) { type in
                            Text(type == .original ? nativeName(source) : type.label).tag(type)
                        }
                        if !source.availablePresentations.contains(draft.presentation) {
                            Text("\(draft.presentation.label) (saved)").tag(draft.presentation)
                        }
                    }
                    .accessibilityIdentifier("data.control.presentation")
                    if preview.presentation != draft.presentation, case .table = source.figure {
                        Text("The available observations are shown in a table.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let label = source.transposeLabel {
                        Toggle(label, isOn: $draft.transpose)
                            .accessibilityIdentifier("data.control.transpose")
                    }
                }
                Section("Dates") {
                    StudyPeriodPicker(
                        period: $draft.period, defaultLabel: id.defaultRangeLabel, calendar: history.calendar,
                        today: history.today,
                        earliest: history.firstDate)
                }
                Section("Focus") {
                    if id.hasMuscleFocus {
                        choiceLink(
                            "Muscles",
                            binding: Binding(
                                get: { draft.muscles.map(\.rawValue) },
                                set: { draft.muscles = $0.compactMap(Muscle.init(rawValue:)) }
                            ), choices: Muscle.allCases.map { .init(key: $0.rawValue, name: $0.rawValue.capitalized) },
                            multiple: true, fallback: defaultMuscles)
                            .accessibilityIdentifier("data.control.muscles")
                    }
                    if id != .legWork {
                        choiceLink(
                            id.exerciseRole,
                            binding: id == .relationship
                                ? Binding(get: { draft.exerciseKeys }, set: { draft.selectHorizontalLift($0) })
                                : $draft.exerciseKeys,
                            choices: exercises,
                            multiple: id.multipleExercises, fallback: id.defaultExerciseLabel)
                            .accessibilityIdentifier("data.control.exercise")
                    }
                    if id == .relationship {
                        choiceLink(
                            "Vertical exercise",
                            binding: Binding(
                                get: { draft.secondExercise.map { [$0] } ?? [] },
                                set: { draft.secondExercise = $0.first }
                            ), choices: exercises.filter { $0.key != draft.horizontalLift }, multiple: false,
                            fallback: "Reverse lunge")
                            .accessibilityIdentifier("data.control.secondExercise")
                    }
                }
                let settings = id.parameters.filter { parameter, _ in
                    draft.period == .original || (parameter != .weeks && parameter != .comparisonDays)
                }
                if !settings.isEmpty {
                    Section("Chart settings") {
                        ForEach(settings, id: \.0) { parameter, fallback in
                            NavigationLink {
                                StudyNumberEditor(
                                    parameter: parameter, id: id, defaultValue: fallback,
                                    unit: history.unit,
                                    value: Binding(
                                        get: { draft.parameters[parameter] },
                                        set: { draft.parameters[parameter] = $0 }))
                            } label: {
                                LabeledContent(parameter.label(for: id), value: text(for: parameter, fallback: fallback))
                            }
                            .accessibilityIdentifier("data.control.\(parameter.rawValue)")
                        }
                    }
                }
                if draft != StudyOptions() {
                    Button("Restore chart defaults") { draft = StudyOptions() }
                }
            }
            .navigationTitle("Customize chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private func nativeName(_ study: StudyResult) -> String {
        switch study.figure {
        case .matrix: "Heatmap (default)"
        case .traces, .liftPanels: "Trend (default)"
        case .bars: "Bars (default)"
        case .table: "Table (default)"
        case .attempts: "Attempt counts (default)"
        case .comparison: "Comparison (default)"
        case nil: "Chart default"
        }
    }

    private func text(for parameter: StudyParameter, fallback: Int?) -> String {
        guard let number = draft.parameters[parameter] ?? fallback else { return "Automatic" }
        return parameter == .load ? history.loadText(number) : number.formatted()
    }

    private var exercises: [StudyChoice] {
        var names: [String: String] = [:]
        for session in history.sessions where !session.done.isEmpty {
            if id == .pushups && !session.repsOnly { continue }
            if [
                .legMax, .records, .fixedSquat, .milestones, .repeatBench, .yearlyRecords, .blocks, .relationship,
                .typicalBench, .forecast, .squatSuccess, .missingEstimates, .tonnage, .lastCurl, .benchSets, .exerciseOrder,
                .returnToSquat, .repMix,
            ].contains(id) && !session.loaded {
                continue
            }
            if id == .substitutions {
                guard let planned = session.planned else { continue }
                names[planned] = history.exerciseName(for: planned)
            } else {
                names[session.key] = session.name
            }
        }
        return names.map { StudyChoice(key: $0.key, name: $0.value) }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var defaultMuscles: String {
        if !draft.exerciseKeys.isEmpty { return "Exercise muscles" }
        switch id {
        case .gluteSources: return "Glutes"
        case .armReps, .repChanges: return StudyHistory.arms.map(\.rawValue).joined(separator: ", ")
        default: return StudyHistory.legs.map(\.rawValue).joined(separator: ", ")
        }
    }

    private func choiceLink(
        _ label: String, binding: Binding<[String]>, choices: [StudyChoice], multiple: Bool, fallback: String
    ) -> some View {
        let keys = binding.wrappedValue
        let text =
            keys.isEmpty
            ? fallback
            : (keys.count > 1 ? "\(keys.count) selected" : choices.first { $0.key == keys.first }?.name ?? "Selected")
        return NavigationLink {
            StudyChoiceList(title: label, fallback: fallback, choices: choices, multiple: multiple, keys: binding)
        } label: {
            LabeledContent(label, value: text)
        }
    }
}

private struct StudyChoice: Identifiable {
    var key: String
    var name: String
    var id: String { key }
}

private struct StudyChoiceList: View {
    let title: String
    let fallback: String
    let choices: [StudyChoice]
    let multiple: Bool
    @Binding var keys: [String]
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let (shown, correction) = SpellingCorrection.results(
            for: search, vocabulary: { choices.map(\.name) }, isEmpty: \.isEmpty
        ) { text in choices.filter { text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) } }
        List {
            Section {
                row("Default · \(fallback)", selected: keys.isEmpty) {
                    keys = []
                    if !multiple { dismiss() }
                }
                ForEach(shown) { item in
                    row(item.name, selected: keys.contains(item.key)) {
                        if !multiple {
                            keys = [item.key]
                            dismiss()
                        } else if keys.contains(item.key) {
                            keys.removeAll { $0 == item.key }
                        } else {
                            keys.append(item.key)
                        }
                    }
                }
            } header: {
                if let correction { SpellingCorrectionNote(correction: correction) }
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find \(title.lowercased())")
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }.contentShape(.rect)
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StudyPeriodPicker: View {
    @Binding var period: StudyPeriod
    let defaultLabel: String
    let calendar: Calendar
    let today: Date
    let earliest: Date
    private enum Kind: String, CaseIterable {
        case original = "Chart default"
        case all = "All history"
        case year = "Year"
        case month = "Month"
        case day = "Day"
    }
    private var year: Int {
        switch period {
        case .year(let value), .month(let value, _), .day(let value, _, _): value
        default: calendar.component(.year, from: today)
        }
    }
    private var month: Int {
        if case .month(_, let number) = period { return number }
        if case .day(_, let number, _) = period { return number }
        return calendar.component(.month, from: today)
    }
    private var kind: Kind {
        switch period {
        case .original: .original
        case .all: .all
        case .year: .year
        case .day: .day
        case .month: .month
        }
    }
    var body: some View {
        Picker(
            "Range",
            selection: Binding(
                get: { kind },
                set: { newKind in
                    switch newKind {
                    case .original: period = .original
                    case .all: period = .all
                    case .year: period = .year(year)
                    case .day: period = .day(year: year, month: month, day: 1)
                    case .month: period = .month(year: year, month: month)
                    }
                })
        ) {
            ForEach(Kind.allCases, id: \.self) { Text($0 == .original ? defaultLabel : $0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("data.control.period")
        if case let .day(year, month, day) = period {
            DatePicker("Date", selection: Binding(get: {
                calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? today
            }, set: { date in
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                if let year = parts.year, let month = parts.month, let day = parts.day {
                    period = .day(year: year, month: month, day: day)
                }
            }), displayedComponents: .date)
        }
        if kind == .year || kind == .month {
            let current = calendar.component(.year, from: today)
            let first = calendar.component(.year, from: earliest)
            Picker(
                "Year",
                selection: Binding(
                    get: { year },
                    set: {
                        period = kind == .month ? .month(year: $0, month: month) : .year($0)
                    })
            ) {
                ForEach((min(year, first, current - 1)...max(year, current)).reversed(), id: \.self) { value in
                    Text(String(value)).tag(value)
                }
            }
            .accessibilityIdentifier("data.control.year")
        }
        if kind == .month {
            Picker("Month", selection: Binding(get: { month }, set: { period = .month(year: year, month: $0) })) {
                ForEach(1...12, id: \.self) { month in Text(calendar.monthSymbols[month - 1]).tag(month) }
            }
            .accessibilityIdentifier("data.control.month")
        }
    }
}

struct StudyNumberEditor: View {
    let parameter: StudyParameter
    let id: TrainingStudy
    let defaultValue: Int?
    let unit: WeightUnit
    @Binding var value: Int?
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    private var initialText: String {
        guard let current = value ?? defaultValue else { return "" }
        return parameter == .load ? unit.format(tenthsPounds: current) : String(current)
    }

    private var resolved: Int? {
        let value = try? Double(text, format: .number)
        guard let number = value, number.isFinite, number >= 0, number <= 100000,
            parameter == .load || number == number.rounded()
        else { return nil }
        let integer = parameter == .load ? unit.tenthsPounds(from: number) : Int(number)
        return parameter.range.contains(integer) ? integer : nil
    }

    var body: some View {
        Form {
            Section {
                TextField(parameter == .load ? "Load in \(unit.symbol)" : parameter.label(for: id), text: $text)
                    .keyboardType(parameter == .load ? .decimalPad : .numberPad)
            }
            Button("Use chart default") {
                value = nil
                dismiss()
            }
        }
        .navigationTitle(parameter.label(for: id)).navigationBarTitleDisplayMode(.inline)
        .onAppear { text = initialText }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if text != initialText { value = resolved }
                    dismiss()
                }.disabled(resolved == nil)
            }
        }
    }
}
