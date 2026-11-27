import SwiftData
import SwiftUI

struct ProgramDataView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.Key.weightUnit) private var unit = WeightUnit.current

    @State private var onScreen = false

    var body: some View {
        // Off screen, keep showing the last history, so logging sets elsewhere doesn't rebuild it.
        let history = onScreen ? nil : StudyHistory.latest
        StudyGallery(history: history ?? StudyHistory.current(in: context, unit: unit))
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }
}

private struct StudyGallery: View {
    let history: StudyHistory
    @AppStorage(SavedStudyViews.storageKey) private var storedOptions = Data()

    private let journal = GallerySearchJournal.shared
    private let model = ChartSearchModel.shared
    @State private var appliedQuery = ""
    @State private var plan: ChartSearchPlan?
    @State private var results = ChartSearchResults()
    @State private var cache = ChartResultCache()
    @State private var path: [GalleryCardID] = []
    @State private var searchEdits: [GalleryCardID: StudyOptions] = [:]

    private func save(_ options: StudyOptions, for id: TrainingStudy) {
        if let data = try? SavedStudyViews(data: storedOptions).saving(options, for: id) {
            storedOptions = data
        }
    }
    @Namespace private var zoom
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: 2)

    /// Everything the results depend on. Search runs when one of these changes, not on every redraw.
    private struct SearchInput: Equatable {
        let text: String
        let plan: ChartSearchPlan?
        let saved: Data
        let revision: Int
    }

    private var searchInput: SearchInput {
        SearchInput(text: appliedQuery, plan: plan, saved: storedOptions, revision: history.revision)
    }

    var body: some View {
        let searching = !appliedQuery.isEmpty
        return NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let note = results.note, searching, !results.isEmpty {
                        Label(note, systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("data.search.note")
                    }
                    if let answer = results.answer {
                        tile(answer, expanded: true)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(results.cards) { tile($0, expanded: false) }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if !searching || !results.isEmpty {
                    EmptyView()
                } else if let note = results.note {
                    ContentUnavailableView("No matching history", systemImage: "chart.xyaxis.line", description: Text(note))
                } else {
                    ContentUnavailableView.search(text: appliedQuery)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GallerySearchField(journal: journal, onFocus: model.prewarm) { text in
                    guard text != appliedQuery else { return }
                    searchEdits.removeAll()
                    plan = nil
                    appliedQuery = text
                }
            }
            .onChange(of: searchInput, initial: true) {
                results = ChartSearch.results(for: ChartQuery(appliedQuery, history: history), plan: plan,
                                              history: history, saved: SavedStudyViews(data: storedOptions),
                                              cache: cache)
            }
            .task {
                // Load the embedding model off the main thread, so the first search doesn't wait for it.
                await Task.detached(priority: .utility) { _ = ExerciseTextEncoder.bundled }.value
                _ = ChartIndex.shared
            }
            .task(id: appliedQuery) { await askModel(appliedQuery) }
            .navigationTitle("Data")
            .navigationDestination(for: GalleryCardID.self) { id in
                if let card = ([results.answer].compactMap { $0 } + results.cards).first(where: { $0.id == id }) {
                    let options = searchEdits[id] ?? card.options
                    let source = searchEdits[id] == nil ? card.result : history.result(for: id.study, options: options)
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

    /// Local results are already on screen. A question can add the model's chart picks a moment later.
    private func askModel(_ input: String) async {
        guard model.isAvailable, ChartSearch.asksModel(ChartQuery(input, history: history)) else { return }
        // A saved plan applies at once. A new one waits for a longer pause, so half-typed questions don't use the model.
        if journal.cachedPlan(input) == nil {
            guard (try? await Task.sleep(for: .milliseconds(350))) != nil else { return }
        }
        let suggestions = results.cards.prefix(4).map(\.id.study)
        let resolved = await journal.resolve(input) {
            try await model.plan(for: input, suggestions: suggestions)
        }
        // Don't reorder charts under someone who has opened or edited one.
        guard !Task.isCancelled, path.isEmpty, searchEdits.isEmpty else { return }
        plan = resolved
    }

    private func tile(_ card: GalleryCard, expanded: Bool) -> some View {
        let options = searchEdits[card.id] ?? card.options
        let study = searchEdits[card.id] == nil ? card.result : history.result(for: card.id.study, options: options)
        let display = study.presented(as: options.presentation, transpose: options.transpose)
        return NavigationLink(value: card.id) {
            VStack(alignment: .leading, spacing: 7) {
                if study.figure != nil {
                    StudyThumbnail(study: display)
                        .aspectRatio(expanded ? 2.2 : 1.65, contentMode: .fit)
                        .powerJackGlassCard()
                        .matchedTransitionSource(id: card.id, in: zoom)
                }
                Text(study.galleryCaption)
                    .font(expanded ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                if expanded {
                    Text(study.summary).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(study.galleryAccessibilityLabel + (expanded ? ". " + study.summary : ""))
        .accessibilityHint(study.figure == nil ? "No matching history. Opens chart details." : "Opens full-size chart.")
        .accessibilityIdentifier(expanded ? "data.answer" : "data.study.\(study.id.rawValue)")
    }
}

struct GallerySearchField: View {
    let journal: GallerySearchJournal
    var onFocus: () -> Void = {}
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
        suggestions = journal.suggestions(for: value)
    }

    private func apply() {
        update(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func record() {
        guard pending else { return }
        journal.record(query)
        recordedInFocus = true
        pending = false
    }

    private func submit(_ value: String) {
        if value != query { edit(value) }
        apply()
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
                        apply()
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
                onFocus()
            } else { record() }
        }
        .task(id: query) {
            // Search once typing pauses, not on every keystroke. Record a search the user stayed on,
            // since a live search can be read without pressing Return.
            do {
                try await Task.sleep(for: .milliseconds(250))
                apply()
                guard typing, pending, !query.isEmpty else { return }
                try await Task.sleep(for: .milliseconds(1250))
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
