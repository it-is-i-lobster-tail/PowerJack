import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FitNotesImportView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.exerciseName) private var exercises: [Exercise]
    @Query(sort: [SortDescriptor(\ImportedSet.trainingDay, order: .reverse), SortDescriptor(\ImportedSet.sourceOrder)])
    private var history: [ImportedSet]
    @State private var index: ExerciseSearch.Index?
    @State private var familiarity = ExerciseFamiliarity.none
    @State private var rows: [FitNotesSet] = []
    @State private var groups: [String: [FitNotesSet]] = [:]
    @State private var names: [String] = []
    @State private var matches: [String: Exercise] = [:]
    @State private var skipped: [String: ImportSkipReason] = [:]
    @State private var suggestions: [String: ImportSuggestion] = [:]
    @State private var ranked: [String: [Exercise]] = [:]
    @State private var selection: String?
    @State private var picking = false
    @State private var loading = false
    @State private var message: String?
    @State private var error: String?
    @State private var reviewID = UUID()
    @State private var onlyUnmatched = true
    @State private var prepared = 0
    @State private var imported: Set<String> = []
    @State private var remembered: [String: Exercise] = [:]
    @State private var rememberedSkips: [String: ImportSkipReason] = [:]

    private var includedSetCount: Int {
        rows.count - skipped.keys.reduce(0) { $0 + (groups[$1]?.count ?? 0) }
    }

    private var toReview: Int { names.count - matches.count - skipped.count }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    Button("Choose FitNotes CSV", systemImage: "doc", action: { picking = true })
                        .disabled(loading)
                    if loading { ProgressView("Reading sets…") }
                    if let message { Text(message) }
                } footer: {
                    Text("Choose an export from Files to import historical sets. Confirm each exercise before saving.")
                }
                if !history.isEmpty {
                    NavigationLink("Imported sets (\(history.count))") { ImportedDataView() }
                }
            } else {
                Section {
                    Text("PowerJack suggests matches for your FitNotes exercises. Confirm each suggestion, choose another exercise, or skip it.")
                        .font(.subheadline)
                    if prepared < names.count {
                        ProgressView("Finding matches · \(prepared) of \(names.count)", value: Double(prepared), total: Double(names.count))
                    }
                    Text("\(matches.count) confirmed · \(skipped.count) skipped · \(toReview) to review")
                    if prepared == names.count && toReview == 0 && includedSetCount == 0 {
                        Text("Nothing new to import.").foregroundStyle(.secondary)
                    } else {
                        Button("Import \(includedSetCount) sets", action: save)
                            .disabled(toReview > 0 || matches.isEmpty)
                    }
                }
                Section {
                    ForEach(names.prefix(prepared).filter { !onlyUnmatched || (matches[$0] == nil && skipped[$0] == nil) }, id: \.self) { name in
                        reviewRow(name)
                            .swipeActions(edge: .leading) { skipAction(name) }
                            .swipeActions(edge: .trailing) { skipAction(name) }
                    }
                } header: {
                    HStack {
                        Text("Match exercises")
                        Spacer()
                        Toggle("Unmatched only", isOn: $onlyUnmatched)
                            .fixedSize()
                    }
                }
            }
        }
        .navigationTitle("FitNotes")
        .background { ExerciseSearchIndexLoader(index: $index, familiarity: $familiarity) }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url): Task { await load(url) }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .navigationDestination(item: $selection) { name in
            FitNotesChoice(name: name, category: groups[name]?.first?.category ?? "",
                           count: groups[name]?.count ?? 0, exercises: exercises, index: index, familiarity: familiarity,
                           choices: choices(name), confirmed: matches[name],
                           skipped: skipped[name], changeSkip: {
                toggleSkip(name)
                selection = nil
            }, unconfirm: {
                unconfirm(name)
                selection = nil
            }) { exercise in
                skipped[name] = nil
                matches[name] = exercise
                selection = nil
            }
        }
        .task(id: index == nil ? nil : reviewID) {
            // Publish each row with its suggestion ready, in file-independent alphabetical order.
            guard let index else { return }
            for name in names.dropFirst(prepared) {
                guard !Task.isCancelled else { return }
                let sets = groups[name] ?? []
                var (suggestion, found, askModel) = FitNotesMatcher.review(
                    name, sets: sets, among: exercises, index: index, familiarity: familiarity, imported: imported,
                    rememberedMatch: remembered[name], rememberedSkip: rememberedSkips[name])
                if askModel,
                   let picked = await FitNotesModel.choose(name: name, category: sets.first?.category ?? "",
                                                           candidates: Array(found.prefix(FitNotesMatcher.modelCandidateCount))) {
                    suggestion = picked
                }
                guard !Task.isCancelled else { return }
                switch suggestion {
                case .skip(let reason): skipped[name] = reason
                case .match(let exercise) where remembered[name] != nil: matches[name] = exercise
                default: break
                }
                found = Array(found.prefix(FitNotesMatcher.modelCandidateCount))
                ranked[name] = found
                suggestions[name] = suggestion
                prepared += 1
                await Task.yield()
            }
        }
        .alert("FitNotes import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    /// The lift a row suggests, when it suggests one.
    private func suggested(_ name: String) -> Exercise? {
        if case .match(let exercise) = suggestions[name] { return exercise }
        return nil
    }

    /// The choices a row offers: its suggestion first, then the best search hits.
    private func choices(_ name: String) -> [Exercise] {
        let first = matches[name] ?? suggested(name)
        let rest = (ranked[name] ?? []).filter { $0 != first }
        return Array(([first].compactMap { $0 } + rest).prefix(FitNotesMatcher.choiceCount))
    }

    private func reviewRow(_ name: String) -> some View {
        let confirmed = matches[name]
        let target = confirmed ?? suggested(name)
        let skip = skipped[name]
        let options = target == nil && skip == nil ? choices(name) : []
        let matchColor: Color = colorScheme == .dark ? .green : Color(red: 0.08, green: 0.43, blue: 0.18)
        let status = Self.status(confirmed: confirmed != nil, skipped: skip != nil, suggested: target != nil,
                                 choiceCount: options.count)
        let shown = skip?.label ?? target?.exerciseName ?? options.first?.exerciseName ?? "No clear match"
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FitNotes CSV").font(.caption).foregroundStyle(.secondary)
                Text(name).font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary)
                if let skip {
                    Label {
                        Text(skip.label).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "forward.fill").imageScale(.small).foregroundStyle(.orange)
                    }
                } else {
                    Text(shown).foregroundStyle(target != nil ? matchColor : Color.secondary)
                }
            }
            .accessibilityHidden(true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            if confirmed != nil {
                Button("Edit") { unconfirm(name) }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 12)
            } else if skip != nil {
                Button("Include") { toggleSkip(name) }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 12)
            } else if let target {
                Button("Confirm") { matches[name] = target }
                    .buttonStyle(.bordered)
                    .tint(matchColor)
                    .padding(.trailing, 12)
            } else {
                Button("Select") { selection = name }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .padding(.trailing, 12)
            }
        }
        .background {
            Button { selection = name } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("FitNotes CSV: \(name). PowerJack: \(skip?.spokenLabel ?? shown)")
            .accessibilityHint("Opens exercise details")
        }
        // Keep the separator under the text even when a skip icon leads the last line.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
        .listRowInsets(EdgeInsets())
        .accessibilityElement(children: .contain)
    }

    /// The small status line under a row's FitNotes name.
    static func status(confirmed: Bool, skipped: Bool, suggested: Bool, choiceCount: Int) -> String {
        if confirmed { return "PowerJack · Confirmed" }
        if skipped { return "PowerJack · Skipped" }
        if suggested { return "PowerJack · Suggested" }
        return choiceCount > 1 ? "PowerJack · \(choiceCount) choices" : "PowerJack"
    }

    private func unconfirm(_ name: String) {
        if let exercise = matches.removeValue(forKey: name) { suggestions[name] = .match(exercise) }
    }

    /// Skipping by hand has no stated reason. Including a skipped row again offers its choices.
    private func toggleSkip(_ name: String) {
        if skipped.removeValue(forKey: name) != nil {
            if case .skip = suggestions[name] { suggestions[name] = .choices(choices(name)) }
        } else {
            unconfirm(name)
            skipped[name] = .chosen
        }
    }

    private func skipAction(_ name: String) -> some View {
        Button(skipped[name] != nil ? "Include again" : "Skip",
               systemImage: skipped[name] != nil ? "arrow.uturn.backward" : "hand.raised.fill") {
            toggleSkip(name)
        }.tint(.orange)
    }

    private func load(_ url: URL) async {
        loading = true
        message = nil
        defer { loading = false }
        do {
            rows = try await FitNotesImport.read(url)
            groups = Dictionary(grouping: rows, by: \.name)
            names = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            matches = [:]
            prepared = 0
            skipped = [:]
            onlyUnmatched = true
            suggestions = [:]
            ranked = [:]
            imported = Set(history.map(\.sourceKey))
            rememberedSkips = FitNotesSkips.load()
            remembered = [:]
            for (name, sets) in Dictionary(grouping: history, by: \.sourceExercise) {
                let keys = Set(sets.map(\.exerciseKey))
                if keys.count == 1, let key = keys.first {
                    remembered[name] = exercises.first { $0.syncKey == key }
                }
            }
            reviewID = UUID()
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let included = rows.filter { skipped[$0.name] == nil }
            let added = try FitNotesImport.save(included, matches: matches, in: context)
            FitNotesSkips.record(skipped: skipped, imported: matches.keys)
            message = "Imported \(added) sets. \(included.count - added) already imported. \(rows.count - included.count) skipped."
            rows = []
            prepared = 0
            names = []
            groups = [:]
            reviewID = UUID()
        } catch { self.error = error.localizedDescription }
    }
}

private struct FitNotesChoice: View {
    let name: String
    let category: String
    let count: Int
    let exercises: [Exercise]
    let index: ExerciseSearch.Index?
    let familiarity: ExerciseFamiliarity
    let choices: [Exercise]
    let confirmed: Exercise?
    let skipped: ImportSkipReason?
    let changeSkip: () -> Void
    let unconfirm: () -> Void
    let choose: (Exercise) -> Void
    @State private var search = ""
    @State private var creating = false

    /// Every exercise when nothing is typed, else the shared search's ranked list.
    private var listed: [Exercise] {
        guard !search.isEmpty, let index else { return exercises }
        let byKey = Dictionary(exercises.map { ($0.searchKey, $0) }, uniquingKeysWith: { first, _ in first })
        let muscle = FitNotesMatcher.primaryMuscle(for: name, category: category)
        return index.rank(ExerciseQuery(search), context: .importing(category: muscle), familiarity: familiarity)
            .compactMap { byKey[$0.key] }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("FitNotes CSV", value: name)
                if let confirmed {
                    LabeledContent("PowerJack", value: confirmed.exerciseName)
                    Button("Unconfirm match", action: unconfirm)
                } else if let skipped {
                    LabeledContent("PowerJack", value: skipped.label)
                }
                Button("Create new exercise", systemImage: "plus") { creating = true }
            } header: {
                Text("\(category) · \(count) sets")
            }
            if search.isEmpty && !choices.isEmpty {
                Section("Suggested matches") {
                    ForEach(choices) { exercise in option(exercise) }
                }
            }
            Section(search.isEmpty ? "All exercises" : "Results") {
                ForEach(listed) { exercise in option(exercise) }
            }
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: changeSkip) {
                    Label(skipped != nil ? "Include again" : "Skip",
                          systemImage: skipped != nil ? "arrow.uturn.backward" : "hand.raised.fill")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel(skipped != nil ? "Include again" : "Skip")
            }
        }
        .searchable(text: $search)
        .sheet(isPresented: $creating) {
            NavigationStack {
                ExerciseNewView(name: name, primaryMuscle: FitNotesMatcher.primaryMuscle(for: name, category: category)) { exercise in
                    creating = false
                    choose(exercise)
                }
            }
        }
    }

    private func option(_ exercise: Exercise) -> some View {
        Button { choose(exercise) } label: {
            VStack(alignment: .leading) {
                Text(exercise.exerciseName)
                Text("\(exercise.equipmentDisplayName) · \(exercise.primaryMuscleFocus.rawValue.capitalized)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
