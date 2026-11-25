import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FitNotesImportView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.exerciseName) private var exercises: [Exercise]
    @Query(sort: [SortDescriptor(\ImportedSet.trainingDay, order: .reverse), SortDescriptor(\ImportedSet.sourceOrder)])
    private var history: [ImportedSet]
    @State private var rows: [FitNotesSet] = []
    @State private var groups: [String: [FitNotesSet]] = [:]
    @State private var names: [String] = []
    @State private var matches: [String: Exercise] = [:]
    @State private var suggestions: [String: Exercise] = [:]
    @State private var selection: String?
    @State private var picking = false
    @State private var loading = false
    @State private var message: String?
    @State private var error: String?
    @State private var reviewID = UUID()
    @State private var skipped: Set<String> = []
    @State private var onlyUnmatched = false
    @State private var prepared = 0
    @State private var remembered: [String: Exercise] = [:]

    private var includedSetCount: Int {
        rows.count - skipped.reduce(0) { $0 + (groups[$1]?.count ?? 0) }
    }

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
                    NavigationLink("Imported sets (\(history.count))") {
                        List(history) { set in
                            VStack(alignment: .leading) {
                                Text(set.exerciseName)
                                Text([set.trainingDay, set.muscle.capitalized,
                                      set.reps.map { "\($0) reps" },
                                      set.weightTenthsPounds.map { "\(WeightUnit.current.format(tenthsPounds: $0)) \(WeightUnit.current.symbol)" },
                                      set.durationSeconds.map { "\($0)s" },
                                      set.distance.map { "\($0.formatted()) \(set.distanceUnit)" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !set.comment.isEmpty { Text(set.comment).font(.footnote) }
                            }
                        }.navigationTitle("Imported sets")
                    }
                }
            } else {
                Section {
                    Text("PowerJack suggests matches for your FitNotes exercises. Confirm each suggestion, choose another exercise, or skip it.")
                        .font(.subheadline)
                    if prepared < names.count {
                        ProgressView("Finding matches · \(prepared) of \(names.count)", value: Double(prepared), total: Double(names.count))
                    }
                    Text("\(matches.count) confirmed · \(skipped.count) skipped · \(names.count - matches.count - skipped.count) to review")
                    Button("Import \(includedSetCount) sets", action: save)
                        .disabled(matches.count + skipped.count != names.count || matches.isEmpty)
                }
                Section {
                    ForEach(names.prefix(prepared).filter { !onlyUnmatched || (matches[$0] == nil && !skipped.contains($0)) }, id: \.self) { name in
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
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url): Task { await load(url) }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .navigationDestination(item: $selection) { name in
            FitNotesChoice(name: name, category: groups[name]?.first?.category ?? "",
                           count: groups[name]?.count ?? 0, exercises: exercises,
                           suggested: suggestions[name], confirmed: matches[name],
                           skipped: skipped.contains(name), changeSkip: {
                toggleSkip(name)
                selection = nil
            }, unconfirm: {
                unconfirm(name)
                selection = nil
            }) { exercise in
                skipped.remove(name)
                matches[name] = exercise
                selection = nil
            }
        }
        .task(id: reviewID) {
            // Publish each row with its recommendation ready, in file-independent alphabetical order.
            for name in names.dropFirst(prepared) {
                guard !Task.isCancelled else { return }
                var suggestion = remembered[name] ?? FitNotesMatcher.direct(name, among: exercises)
                if suggestion == nil {
                    suggestion = await FitNotesMatcher.recommend(name, category: groups[name]?.first?.category ?? "",
                                                                  among: exercises)
                }
                guard !Task.isCancelled else { return }
                suggestions[name] = suggestion
                prepared += 1
                await Task.yield()
            }
        }
        .alert("FitNotes import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func reviewRow(_ name: String) -> some View {
        let confirmed = matches[name]
        let target = confirmed ?? suggestions[name]
        let isSkipped = skipped.contains(name)
        let matchColor: Color = colorScheme == .dark ? .green : Color(red: 0.08, green: 0.43, blue: 0.18)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FitNotes CSV").font(.caption).foregroundStyle(.secondary)
                Text(name).font(.headline)
                Text(confirmed != nil ? "PowerJack · Confirmed" :
                        target != nil && !isSkipped ? "PowerJack · Suggested" : "PowerJack")
                    .font(.caption).foregroundStyle(.secondary)
                Text(isSkipped ? "Don’t Import" : target?.exerciseName ?? "-")
                    .foregroundStyle(isSkipped || target == nil ? Color.secondary : matchColor)
            }
            .accessibilityHidden(true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            if confirmed != nil {
                Button("Unconfirm") { unconfirm(name) }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 12)
            } else if !isSkipped, let target {
                Button("Confirm") { matches[name] = target }
                    .buttonStyle(.bordered)
                    .tint(matchColor)
                    .padding(.trailing, 12)
            } else if !isSkipped {
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
            .accessibilityLabel("FitNotes CSV: \(name). PowerJack: \(isSkipped ? "Don’t Import" : target?.exerciseName ?? "No clear match")")
            .accessibilityHint("Opens exercise details")
        }
        .listRowInsets(EdgeInsets())
        .accessibilityElement(children: .contain)
    }

    private func unconfirm(_ name: String) {
        suggestions[name] = matches.removeValue(forKey: name)
    }

    private func toggleSkip(_ name: String) {
        if skipped.remove(name) == nil {
            if matches[name] != nil { unconfirm(name) }
            skipped.insert(name)
        }
    }

    private func skipAction(_ name: String) -> some View {
        Button(skipped.contains(name) ? "Include again" : "Don’t Import",
               systemImage: skipped.contains(name) ? "arrow.uturn.backward" : "hand.raised.fill") {
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
            skipped = []
            onlyUnmatched = false
            suggestions = [:]
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
            let included = rows.filter { !skipped.contains($0.name) }
            let added = try FitNotesImport.save(included, matches: matches, in: context)
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
    let suggested: Exercise?
    let confirmed: Exercise?
    let skipped: Bool
    let changeSkip: () -> Void
    let unconfirm: () -> Void
    let choose: (Exercise) -> Void
    @State private var search = ""
    @State private var creating = false

    var body: some View {
        List {
            Section {
                LabeledContent("FitNotes CSV", value: name)
                if let confirmed {
                    LabeledContent("PowerJack", value: confirmed.exerciseName)
                    Button("Unconfirm match", action: unconfirm)
                }
                Button("Create new exercise", systemImage: "plus") { creating = true }
            } header: {
                Text("\(category) · \(count) sets")
            }
            if search.isEmpty {
                Section(suggested == nil && confirmed == nil ? "Low-confidence alternatives" : "Suggested matches") {
                    ForEach(FitNotesMatcher.selectorChoices(name, category: category, among: exercises,
                                                            preferred: confirmed ?? suggested)) { exercise in
                        option(exercise)
                    }
                }
            }
            Section("All exercises") {
                ForEach(exercises.filter { search.isEmpty || $0.exerciseName.localizedCaseInsensitiveContains(search) }) { exercise in
                    option(exercise)
                }
            }
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: changeSkip) {
                    Label(skipped ? "Include again" : "Don’t Import",
                          systemImage: skipped ? "arrow.uturn.backward" : "hand.raised.fill")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel(skipped ? "Include again" : "Don’t Import")
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
