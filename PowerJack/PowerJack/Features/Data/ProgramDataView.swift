import SwiftData
import SwiftUI

struct ProgramDataView: View {
    @Query private var programs: [Program]
    @Query private var logs: [WorkoutLog]
    @Query private var archived: [HistoryRecord]
    @AppStorage(AppSettings.Key.weightUnit) private var unit = WeightUnit.current

    var body: some View {
        let history = StudyHistory(programs: programs, archive: archived, logs: logs, unit: unit)
        StudyGallery(history: history)
    }
}

private struct StudyGallery: View {
    let history: StudyHistory
    @AppStorage(SavedStudyViews.storageKey) private var storedOptions = Data()

    @Query private var exercises: [Exercise]
    @State private var index: ExerciseChartSearch.Index?
    private let journal = GallerySearchJournal.shared
    @State private var appliedQuery = ""
    @State private var question: StudyQuestion?
    @State private var path: [GalleryCardID] = []
    @State private var searchEdits: [GalleryCardID: StudyOptions] = [:]

    private func save(_ options: StudyOptions, for id: TrainingStudy) {
        if let data = try? SavedStudyViews(data: storedOptions).saving(options, for: id) {
            storedOptions = data
        }
    }
    @Namespace private var zoom
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: 2)

    var body: some View {
        let choices = SavedStudyViews(data: storedOptions)
        let searching = !appliedQuery.isEmpty
        let cards: [GalleryCard]
        let missingNote: String?
        let consultModel: Bool
        if searching {
            let search = StudySearch(query: appliedQuery, history: history, exercises: exercises, index: index)
            let parsed = LoggedStudyQuestion(appliedQuery, history: history, knownNames: search.knownExerciseNames)
            missingNote = parsed.missingHistoryNote(history)
            if let question {
                consultModel = false
                cards = search.questionCards(question, query: appliedQuery, history: history,
                                             exercises: exercises, saved: choices, parsed: parsed)
            } else {
                cards = search.galleryCards(history: history, saved: choices, parsed: parsed)
                consultModel = StudySearch.needsToolReview(cards, parsed: parsed, history: history)
            }
        } else {
            consultModel = false
            missingNote = nil
            cards = TrainingStudy.allCases.map { study in
                GalleryCard(id: GalleryCardID(study: study, exerciseKeys: []), options: choices[study],
                            source: nil, score: 0, variant: 0)
            }
        }
        let focused = cards.count == 1 && cards.first?.source?.question != nil
        return NavigationStack(path: $path) {
            ScrollView {
                if let missingNote, !cards.isEmpty {
                    Label(missingNote, systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                        .accessibilityIdentifier("data.search.missingHistory")
                }
                LazyVGrid(columns: focused ? [GridItem(.flexible())] : columns, alignment: .leading, spacing: 20) {
                    ForEach(cards) { card in
                        let id = card.id.study
                        let options = searchEdits[card.id] ?? card.options
                        let study = (searchEdits[card.id] == nil ? card.source : nil) ?? history.result(for: id, options: options)
                        let display = study
                            .presented(as: options.presentation, transpose: options.transpose)
                        NavigationLink(value: card.id) {
                            VStack(alignment: .leading, spacing: 7) {
                                if study.figure != nil || !focused {
                                    StudyThumbnail(study: display)
                                        .aspectRatio(1.65, contentMode: .fit)
                                        .powerJackGlassCard()
                                        .matchedTransitionSource(id: card.id, in: zoom)
                                }
                                if card.related {
                                    Text("Related chart").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(study.galleryCaption)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 3)
                                if focused {
                                    Text(study.summary).font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(card.related ? "Related chart, " + study.galleryAccessibilityLabel : study.galleryAccessibilityLabel + (focused ? ". " + study.summary : ""))
                        .accessibilityHint(
                            study.figure == nil ? "No matching history. Opens chart details." : "Opens full-size chart."
                        )
                        .accessibilityIdentifier("data.study.\(study.id.rawValue)")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if cards.isEmpty, let missingNote {
                    ContentUnavailableView("No matching history", systemImage: "chart.xyaxis.line", description: Text(missingNote))
                } else if cards.isEmpty, question != nil, let reason = StudyQuestion.missingMeasurement(for: appliedQuery) {
                    ContentUnavailableView("No matching chart", systemImage: "chart.xyaxis.line",
                                           description: Text(reason))
                } else if cards.isEmpty {
                    ContentUnavailableView.search(text: appliedQuery)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GallerySearchField(journal: journal) { text in
                    guard text != appliedQuery else { return }
                    searchEdits.removeAll()
                    question = nil
                    appliedQuery = text
                }
            }
            .background { ExerciseSearchIndexLoader(index: $index) }
            .task(id: appliedQuery) {
                let input = appliedQuery
                guard consultModel, question == nil, searchEdits.isEmpty else { return }
                do {
                    if let cached = journal.cached(input) {
                        question = cached.plan
                        if Date.now.timeIntervalSince(cached.date) < GallerySearchJournal.lifetime { return }
                    }
                    try await Task.sleep(for: .milliseconds(450))
                    let search = StudySearch(query: input, history: history, exercises: exercises, index: index)
                    let parsed = LoggedStudyQuestion(input, history: history, knownNames: search.knownExerciseNames)
                    let tools = StudySearchTools(search: search, history: history, exercises: exercises, saved: choices, parsed: parsed)
                    let plan = await journal.resolve(input) { query in
                        try await StudyQuestionInterpreter.interpret(query, context: tools)
                    }
                    guard !Task.isCancelled, input == appliedQuery, path.isEmpty, searchEdits.isEmpty else { return }
                    question = plan
                } catch { /* The local search is already visible. */ }
            }
            .navigationTitle("Data")
            .navigationDestination(for: GalleryCardID.self) { id in
                if let card = cards.first(where: { $0.id == id }) {
                    let options = searchEdits[id] ?? card.options
                    let source = (searchEdits[id] == nil ? card.source : nil) ?? history.result(for: id.study, options: options)
                    let study = source.presented(as: options.presentation, transpose: options.transpose)
                    StudyDetail(study: study, source: source, history: history, options: options,
                                saveSearchView: searching && study.question == nil ? { save(options, for: id.study) } : nil) { updated in
                        if searching { searchEdits[id] = updated } else { save(updated, for: id.study) }
                    }
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
            }
        }
    }
}

struct GallerySearchField: View {
    let journal: GallerySearchJournal
    let update: (String) -> Void
    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var pending = false
    @State private var recordedInFocus = false
    @FocusState private var typing: Bool

    private func edit(_ value: String) {
        query = value
        pending = true
        recordedInFocus = false
        update(value.trimmingCharacters(in: .whitespacesAndNewlines))
        suggestions = journal.suggestions(for: value)
    }

    private func record() {
        guard pending else { return }
        journal.record(query)
        recordedInFocus = true
        pending = false
    }

    private func submit(_ value: String) {
        if value != query { edit(value) }
        if !recordedInFocus { pending = true }
        record()
        typing = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if (typing || query.isEmpty), !suggestions.isEmpty {
                Text(query.isEmpty ? "Recent searches" : "Matching searches")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(suggestions, id: \.self) { phrase in
                    Button { submit(phrase) } label: {
                        Label(phrase, systemImage: query.isEmpty ? "clock" : "arrow.up.left")
                            .font(.subheadline).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Fills the search field and shows its charts.")
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search charts", text: Binding(get: { query }, set: edit))
                    .focused($typing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { submit(query) }
                    .accessibilityIdentifier("data.search")
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        record()
                        edit("")
                    }
                    .labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .onAppear { suggestions = journal.suggestions(for: query) }
        .onChange(of: typing) { _, focused in
            if focused {
                recordedInFocus = false
                suggestions = journal.suggestions(for: query)
            } else { record() }
        }
        .task(id: query) {
            // A live search can be read without pressing Return. Do not record each keystroke.
            guard typing, pending, !query.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(1500))
                record()
            } catch { }
        }
        .onDisappear { record() }
    }
}

/// Rasterize only the visible tiles, at the device scale and in its current appearance.
private struct StudyThumbnail: View {
    let study: StudyResult
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @State private var image: Image?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if let image { image.resizable() } else { StudyFigureView(study: study, compact: true).padding(10) }
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: ThumbnailInput(size: size, scheme: scheme, scale: scale, study: study), initial: true) {
                guard size.width > 0, size.height > 0 else { return }
                let content = StudyFigureView(study: study, compact: true)
                    .padding(10).frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = scale
                image = renderer.cgImage.map { Image(decorative: $0, scale: scale) }
            }
        }
        .accessibilityHidden(true)
    }

    private struct ThumbnailInput: Equatable {
        var size: CGSize
        var scheme: ColorScheme
        var scale: CGFloat
        var study: StudyResult
    }
}

private struct StudyDetail: View {
    let study: StudyResult
    let source: StudyResult
    let history: StudyHistory
    let options: StudyOptions
    let saveSearchView: (() -> Void)?
    let apply: (StudyOptions) -> Void
    @State private var customizing = false
    @State private var fullscreen = false
    @State private var editingReps = false
    @State private var editingDates = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(study.displayTitle).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(study.scope).font(.subheadline).foregroundStyle(.secondary)
                    if !study.summary.isEmpty { Text(study.summary).font(.body) }
                    if study.question == nil { quickControls }
                    if study.question == nil || study.figure != nil { chart }
                    if let data = underlyingValues {
                        DisclosureGroup("Values (\(data.rows.count))") {
                            StudyTableView(table: data).padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            StudyReadingGuide(study: study)
        }
        .navigationTitle("Chart").navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let saveSearchView {
                    Menu {
                        Button("Save as default chart view", action: saveSearchView)
                    } label: { Label("Chart actions", systemImage: "ellipsis.circle") }
                }
                if study.question == nil {
                    Button("Customize chart", systemImage: "slider.horizontal.3") { customizing = true }
                }
                if study.figure != nil {
                    Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { fullscreen = true }
                }
            }
        }
        .sheet(isPresented: $customizing) {
            StudyCustomizationView(id: study.id, history: history, apply: apply, draft: options)
        }
        .fullScreenCover(isPresented: $fullscreen) { StudyFullscreenView(study: study, title: study.displayTitle) }
        .accessibilityIdentifier("data.detail.\(study.id.rawValue)")
    }

    private var quickControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { controlItems }
            VStack(alignment: .leading) { controlItems }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .sheet(isPresented: $editingReps) {
            NavigationStack {
                StudyNumberEditor(parameter: .reps, id: study.id, defaultValue: defaultReps,
                                  unit: history.unit, value: Binding(
                                    get: { options.parameters[.reps] },
                                    set: { var updated = options; updated.parameters[.reps] = $0; apply(updated) }))
            }
            .presentationDetents([.medium])
        }
        .popover(isPresented: $editingDates) {
            VStack(alignment: .leading) {
                StudyPeriodPicker(period: Binding(
                    get: { options.period },
                    set: { var updated = options; updated.period = $0; apply(updated) }),
                    defaultLabel: study.id.defaultRangeLabel, calendar: history.calendar,
                    today: history.today, earliest: history.firstDate)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var defaultReps: Int? {
        study.id.parameters.first(where: { $0.0 == .reps })?.1
    }

    @ViewBuilder private var controlItems: some View {
        Button(options.period == .original ? "Dates" : options.period.label, systemImage: "calendar") {
            editingDates = true
        }
        if study.id.parameters.contains(where: { $0.0 == .reps }) {
            let target = options.parameters[.reps] ?? defaultReps
            Button(target.map { "\($0) reps" } ?? "Rep target") { editingReps = true }
        }
        if source.availablePresentations.count > 1 {
            Menu {
                Picker("Chart view", selection: Binding(
                    get: { study.presentation },
                    set: { var updated = options; updated.presentation = $0; apply(updated) })
                ) {
                    ForEach(source.availablePresentations, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
            } label: {
                Label(study.presentation == .original ? "View" : study.presentation.label, systemImage: "chart.xyaxis.line")
            }
            .accessibilityLabel("Chart view")
        }
    }

    @ViewBuilder private var chart: some View {
        let view = StudyFigureView(study: study, compact: false)
        switch study.figure {
        case .traces(let series, _):
            view.frame(height: 290)
            legend(series.map(\.name))
        case .bars(let bars):
            view.frame(height: 270)
            let labels = bars.reduce(into: [String]()) {
                if !$1.group.isEmpty && !$0.contains($1.group) { $0.append($1.group) }
            }
            if !labels.isEmpty { legend(labels) }
        case .comparison(let points, _):
            view.frame(height: max(160, CGFloat(Set(points.map(\.category)).count) * 54))
            legend(points.map(\.series).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } })
        case .matrix:
            ScrollView(.horizontal) { view }
        case .liftPanels, .attempts, .table, nil: view
        }
    }

    private func legend(_ labels: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                HStack(spacing: 6) {
                    Circle().fill(WorkoutChartPalette.color(at: i, scheme: scheme)).frame(width: 8, height: 8)
                    Text(label).font(.caption)
                }
            }
        }
    }

    private var underlyingValues: StudyTable? {
        if case .table = study.figure { return nil }
        return study.detail ?? study.plottedValues
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview("Data Gallery · Sample Training History") {
    let store = PowerJackStore(inMemory: true)
    let seeded = Result { try SimulatorTrainingHistory.populate(in: store.container.mainContext) }

    switch seeded {
    case .success:
        ProgramDataView()
            .modelContainer(store.container)
    case .failure(let error):
        ContentUnavailableView {
            Label("Sample history unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        }
    }
}
#endif
