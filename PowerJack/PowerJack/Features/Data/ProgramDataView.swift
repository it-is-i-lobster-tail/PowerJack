import SwiftData
import SwiftUI

struct ProgramDataView: View {
    private enum Mode: String, CaseIterable {
        case volume = "Volume"
        case targets = "Targets"
        case oneRepMax = "One Rep Max"
    }

    private enum Filter: String, Identifiable {
        case muscles = "Muscle groups"
        case programTypes = "Program type"

        var id: Self { self }
    }

    @Query private var programs: [Program]
    @Query private var logs: [WorkoutLog]
    @State private var searchText = ""
    @State private var searchIndex: ExerciseChartSearch.Index?
    @AppStorage(AppSettings.Key.weightUnit) private var unit = WeightUnit.current
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var mode = Mode.volume
    @State private var isLandscape = false

    @State private var selectedRange = VolumeRange.currentProgram
    @State private var selectedMuscles: Set<Muscle> = []
    @State private var selectedProgramTypes: Set<TemplateType> = []
    @State private var openFilter: Filter?

    private var currentProgram: Program? { programs.active }
    private var range: VolumeRange {
        selectedRange == .currentProgram && currentProgram == nil ? .days30 : selectedRange
    }
    private var matchingPrograms: [Program] {
        programs.filter { matchesProgramType($0) }
    }

    private func matchesProgramType(_ program: Program) -> Bool {
        selectedProgramTypes.isEmpty || selectedProgramTypes.contains(program.templateType)
    }

    var body: some View {
        let query = DataSearchQuery(searchText)
        let search = searchIndex?.results(for: query.exerciseText)
        let isSearching = query.dateFilter != nil || search != nil
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search by muscle, date, exercise, or intent", text: $searchText)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("dataExerciseSearch")
                    if !searchText.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { searchText = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary, in: .capsule)
                .padding(.horizontal)
                .padding(.bottom, 8)
                Picker("Data view", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: verticalSize == .compact ? 480 : .infinity)
                .padding(.horizontal)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if searchIndex == nil && !query.exerciseText.isEmpty {
                            ProgressView("Preparing search")
                        } else {
                            switch mode {
                            case .volume:
                                let matchingLogs = WeeklyVolume.logs(logs, matching: selectedProgramTypes, programs: programs)
                                let excludesCurrent = query.dateFilter == nil && range == .currentProgram
                                    && currentProgram.map { !matchesProgramType($0) } == true
                                if let search, search.muscles.isEmpty || (!selectedMuscles.isEmpty && selectedMuscles.isDisjoint(with: search.muscles)) {
                                    searchEmpty
                                } else {
                                    VolumeView(logs: excludesCurrent ? [] : matchingLogs,
                                           currentProgram: currentProgram, range: range, dateFilter: query.dateFilter,
                                           selectedMuscles: selectedMuscles,
                                           searchMuscles: search?.muscles, isLandscape: isLandscape)
                                }
                            case .targets:
                                Text("Target vs. Actual").font(.title2.bold())
                                if query.dateFilter == nil, range == .currentProgram,
                                   let program = currentProgram, matchesProgramType(program) {
                                    Text(program.templateName).foregroundStyle(.secondary)
                                }
                                let histories = ProgramExerciseHistory.exercises(
                                    in: matchingPrograms, range: range, dateFilter: query.dateFilter,
                                    primaryMuscles: selectedMuscles, search: search
                                ).filter { history in
                                    !isSearching || history.sets.contains { set in
                                        (set.targetReps != nil && set.reps != nil) || (set.targetLoad != nil && set.load != nil)
                                    }
                                }
                                if histories.isEmpty {
                                    if isSearching { searchEmpty } else {
                                        Text("No working sets logged in this range.").foregroundStyle(.secondary)
                                    }
                                } else {
                                    ForEach(histories) { exercise in
                                        if exercise.sets.isEmpty {
                                            VStack(alignment: .leading) {
                                                Text(exercise.name).font(.headline)
                                                Text("No working sets logged yet.").foregroundStyle(.secondary)
                                            }
                                        } else {
                                            ExerciseHistoryChart(exercise: exercise, unit: unit)
                                        }
                                        Divider()
                                    }
                                }
                            case .oneRepMax:
                                Text("1 Rep Max (estimated)")
                                    .font(.title2.bold())
                                    .accessibilityAddTraits(.isHeader)
                                let now = Date.now
                                let visible = ProgramExerciseHistory.exercises(
                                    in: matchingPrograms, range: range, dateFilter: query.dateFilter,
                                    primaryMuscles: selectedMuscles, search: search, now: now
                                ).filter { $0.personalBest != nil }
                                if isSearching && visible.isEmpty { searchEmpty }
                                let allHistory = ProgramExerciseHistory.exercises(
                                    in: matchingPrograms, range: nil, primaryMuscles: selectedMuscles, search: search, now: now
                                )
                                let bests = Dictionary(uniqueKeysWithValues: allHistory.compactMap { exercise in
                                    exercise.personalBest.map { (exercise.id, $0) }
                                })
                                ForEach(visible) { exercise in
                                    if let chart = OneRepMaxChart(exercise: exercise, personalBest: bests[exercise.id], unit: unit) {
                                        chart
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(mode)
                .scrollDismissesKeyboard(.interactively)
            }
            .background { DataSearchIndexLoader(index: $searchIndex) }
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.size.width > geometry.size.height
            } action: { isLandscape = $0 }
            .navigationTitle("Data")
            .navigationBarTitleDisplayMode(verticalSize == .compact ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    dateRangeMenu(for: query)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    muscleGroupsAction
                }
                .visibilityPriority(.low)
                ToolbarOverflowMenu {
                    programTypesAction
                }
            }
        }
        .sheet(item: $openFilter) { filter in
            NavigationStack {
                List {
                    switch filter {
                    case .muscles:
                        filterOptions("All muscles", choices: Muscle.allCases.sorted { $0.rawValue < $1.rawValue },
                                      selected: $selectedMuscles, title: { $0.rawValue.capitalized })
                    case .programTypes:
                        filterOptions("All program types", choices: TemplateType.allCases,
                                      selected: $selectedProgramTypes, title: \.name)
                    }
                }
                .navigationTitle(filter.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { openFilter = nil }
                    }
                }
            }
        }
    }

    private var searchEmpty: some View {
        Text("No matching charts for these filters.").foregroundStyle(.secondary)
    }

    private func dateRangeMenu(for query: DataSearchQuery) -> some View {
        Menu("Date range", systemImage: "calendar") {
            Picker("Date range", selection: Binding<VolumeRange?>(get: {
                query.dateFilter == nil ? range : nil
            }, set: { option in
                guard let option else { return }
                selectedRange = option
                if query.dateFilter != nil { searchText = query.exerciseText }
            })) {
                if let dateFilter = query.dateFilter {
                    Text(dateFilter.name).tag(Optional<VolumeRange>.none).disabled(true)
                }
                ForEach(VolumeRange.allCases.filter { $0 != .currentProgram || currentProgram != nil }) { option in
                    Text(option.name).tag(Optional(option))
                }
            }
            .pickerStyle(.inline)
        }
        .accessibilityValue(query.dateFilter?.name ?? range.name)
    }

    private var muscleGroupsAction: some View {
        Button("Muscle groups", systemImage: "line.3.horizontal.decrease") {
            openFilter = .muscles
        }
        .accessibilityValue(selectedMuscles.isEmpty ? "All muscles" : "\(selectedMuscles.count) selected")
    }

    private var programTypesAction: some View {
        Button("Program type", systemImage: "list.bullet.rectangle") {
            openFilter = .programTypes
        }
        .accessibilityValue(selectedProgramTypes.isEmpty ? "All program types" : "\(selectedProgramTypes.count) selected")
    }

    @ViewBuilder
    private func filterOptions<Option: Identifiable & Hashable>(
        _ allTitle: String, choices: [Option], selected: Binding<Set<Option>>, title: @escaping (Option) -> String
    ) -> some View {
        Section {
            filterOption(allTitle, isSelected: selected.wrappedValue.isEmpty) {
                selected.wrappedValue.removeAll()
            }
        }
        Section {
            ForEach(choices) { option in
                filterOption(title(option), isSelected: selected.wrappedValue.contains(option)) {
                    if selected.wrappedValue.remove(option) == nil { selected.wrappedValue.insert(option) }
                }
            }
        }
    }

    private func filterOption(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Watches catalog edits independently of the text field. All inference and
/// document preparation happen once per catalog revision, off the UI thread.
private struct DataSearchIndexLoader: View {
    @Query private var exercises: [Exercise]
    @Binding var index: ExerciseChartSearch.Index?

    var body: some View {
        let documents = exercises.map(ExerciseChartSearch.Document.init)
        Color.clear.task(id: documents) {
            let build = Task.detached(priority: .userInitiated) { ExerciseChartSearch.Index(documents) }
            let updated = await build.value
            if !Task.isCancelled { index = updated }
        }
    }
}

#if DEBUG
#Preview("Data · Physique") {
    ProgramDataView()
        .modelContainer(PowerJackSeed.trainingHistory())
}

#Preview("Data · Physique Landscape", traits: .landscapeLeft) {
    ProgramDataView()
        .modelContainer(PowerJackSeed.trainingHistory())
}
#endif
