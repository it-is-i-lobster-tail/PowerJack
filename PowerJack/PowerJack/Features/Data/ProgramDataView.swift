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
    @AppStorage(FavoriteCharts.storageKey) private var storedFavorites = Data()

    private let journal = GallerySearchJournal.shared
    private let model = ChartSearchModel.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var recent: [String] = []
    @State private var lastRecorded = ""
    @State private var appliedQuery = ""
    @State private var plan: ChartSearchPlan?
    @State private var results = ChartSearchResults()
    /// The spelling fix the results are for, when the search as typed found nothing.
    @State private var correction: String?
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

    /// A search shows its best charts first. The rest wait behind a row.
    private static let shownCharts = 6
    @State private var showsAllCharts = false

    private var favorites: [GalleryCard] {
        FavoriteCharts(data: storedFavorites).charts.map { favorite in
            GalleryCard(id: GalleryCardID(study: favorite.study, exerciseKeys: favorite.options.exerciseKeys, favorite: favorite.id),
                        options: favorite.options, result: cache.result(for: favorite.study, options: favorite.options, in: history))
        }
    }

    var body: some View {
        let searching = !appliedQuery.isEmpty
        let starting = query.isEmpty && searchFocused
        let favorites = searching ? [] : favorites
        let filled = results.cards.filter { $0.result.figure != nil }
        let empty = searching ? results.cards.filter { $0.result.figure == nil } : []
        let shown = searching && !showsAllCharts ? Array(filled.prefix(Self.shownCharts)) : searching ? filled : results.cards
        return NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if starting {
                        DataSearchStart(recent: recent, ideas: SearchIdeas.make(from: history), run: run) {
                            journal.clearRecent()
                            recent = []
                            lastRecorded = ""
                        }
                    } else {
                        if searching { reading }
                        if !favorites.isEmpty {
                            Text("Favorites").font(.title3.bold())
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(favorites) { tile($0, expanded: false) }
                            }
                            Text("All charts").font(.title3.bold()).padding(.top, 8)
                        }
                        if let answer = results.answer {
                            tile(answer, expanded: true)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(shown) { tile($0, expanded: false) }
                        }
                        if shown.count < filled.count {
                            Button("All \(filled.count) charts for \(scopeName)") { showsAllCharts = true }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityIdentifier("data.search.all")
                        }
                        if !empty.isEmpty {
                            DisclosureGroup("\(empty.count) \(empty.count == 1 ? "chart has" : "charts have") no data for this search") {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                    ForEach(empty) { tile($0, expanded: false) }
                                }
                                .padding(.top, 12)
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("data.search.empty")
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if !starting, searching, results.isEmpty, results.note == nil, results.suggestion == nil, results.scope.isEmpty {
                    ContentUnavailableView.search(text: appliedQuery)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Lift, muscle, date, or chart")
            .searchAutocorrects()
            .searchFocused($searchFocused)
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { run(query) }
            .onChange(of: searchFocused) { _, focused in
                if focused {
                    recent = journal.suggestions(for: "", limit: 5)
                    model.prewarm()
                } else {
                    record()
                }
            }
            .task(id: query) {
                // Search once typing pauses, not on every keystroke. Record a search the lifter stayed on,
                // since a live search can be read without pressing Search.
                guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
                apply(query)
                guard searchFocused, (try? await Task.sleep(for: .milliseconds(1250))) != nil else { return }
                record()
            }
            .onDisappear { record() }
            .onChange(of: searchInput, initial: true) {
                let saved = SavedStudyViews(data: storedOptions)
                (results, correction) = SpellingCorrection.results(
                    for: appliedQuery, vocabulary: { Array(Set(history.sessions.map(\.name))) },
                    isEmpty: { $0.isEmpty && $0.suggestion == nil }
                ) { text in
                    ChartSearch.results(for: ChartQuery(text, history: history), plan: plan,
                                        history: history, saved: saved, cache: cache)
                }
            }
            .task {
                // Load the embedding model off the main thread, so the first search doesn't wait for it.
                await Task.detached(priority: .utility) { _ = ExerciseTextEncoder.bundled }.value
                _ = ChartIndex.shared
            }
            .task(id: appliedQuery) { await askModel(appliedQuery) }
            .navigationTitle("Data")
            .navigationDestination(for: GalleryCardID.self) { id in
                if let card = ([results.answer].compactMap { $0 } + favorites + results.cards).first(where: { $0.id == id }) {
                    let options = searchEdits[id] ?? card.options
                    let source = searchEdits[id] == nil ? card.result : history.result(for: id.study, options: options)
                    let study = source.presented(as: options.presentation, transpose: options.transpose)
                    let keepsEdits = searching || id.favorite != nil
                    StudyDetail(study: study, source: source, history: history, options: options,
                                saveSearchView: searching && study.question == nil ? { save(options, for: id.study) } : nil,
                                isFavorite: FavoriteCharts(data: storedFavorites).favorite(id.study, options: options) != nil,
                                toggleFavorite: { toggleFavorite(id.study, options: options, name: study.displayTitle) }) { updated in
                        if keepsEdits { searchEdits[id] = updated } else { save(updated, for: id.study) }
                    }
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
            }
        }
    }

    /// Shows the charts for the text once typing pauses.
    private func apply(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != appliedQuery else { return }
        searchEdits.removeAll()
        plan = nil
        showsAllCharts = false
        appliedQuery = text
    }

    /// Runs a search chosen from a row, a chip or "Did you mean", and keeps it in the recent searches.
    private func run(_ text: String) {
        query = text
        apply(text)
        record()
        searchFocused = false
    }

    private func record() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastRecorded else { return }
        journal.record(text)
        lastRecorded = text
    }

    private func toggleFavorite(_ study: TrainingStudy, options: StudyOptions, name: String) {
        if let data = try? FavoriteCharts(data: storedFavorites).toggling(study, options: options, name: name) {
            storedFavorites = data
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

    private var scopeName: String {
        results.scope.isEmpty ? "this search" : results.scope.map(\.label).joined(separator: " · ")
    }

    /// What the search read, why nothing matched, and what to try instead.
    @ViewBuilder private var reading: some View {
        if let correction {
            SpellingCorrectionNote(correction: correction)
        }
        if !results.scope.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(results.scope) { chip in
                        Menu {
                            ForEach(chip.alternatives, id: \.self) { choice in
                                Button(choice.name) { run(choice.text) }
                            }
                            if !chip.alternatives.isEmpty { Divider() }
                            Button("Remove", systemImage: "xmark", role: .destructive) { run(chip.removed) }
                        } label: {
                            Text(chip.label).font(.subheadline).lineLimit(1)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Search reads \(chip.label)")
                        .accessibilityHint(chip.isLift ? "Choose another lift or remove it from the search." : "Remove it from the search.")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("data.search.scope")
        }
        if let note = results.note {
            Label(note, systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("data.search.note")
        }
        if let suggestion = results.suggestion {
            Button { run(suggestion.text) } label: {
                Label("Did you mean \(suggestion.name)?", systemImage: "arrow.up.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHint("Searches for \(suggestion.text).")
            .accessibilityIdentifier("data.search.suggestion")
        }
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
        .contextMenu {
            if let favorite = card.id.favorite {
                Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) {
                    if let data = try? FavoriteCharts(data: storedFavorites).removing(favorite) { storedFavorites = data }
                }
            }
        }
        .accessibilityLabel(study.galleryAccessibilityLabel + (expanded ? ". " + study.summary : ""))
        .accessibilityHint(study.figure == nil ? "No matching history. Opens chart details." : "Opens full-size chart.")
        .accessibilityIdentifier(card.id.favorite != nil ? "data.favorite.\(study.id.rawValue)"
                                 : expanded ? "data.answer" : "data.study.\(study.id.rawValue)")
    }
}

/// What an empty search offers: the lifter's recent searches and a few to try.
struct DataSearchStart: View {
    let recent: [String]
    let ideas: [String]
    let run: (String) -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !recent.isEmpty {
                section("Recent searches", rows: recent, icon: "clock.arrow.circlepath") {
                    Button("Clear", action: clear).font(.subheadline)
                }
            }
            section("Try a search", rows: ideas, icon: "magnifyingglass") { EmptyView() }
        }
    }

    private func section(_ title: String, rows: [String], icon: String,
                         @ViewBuilder trailing: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, text in
                    if index > 0 { Divider().padding(.leading, 48) }
                    Button { run(text) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
                            Text(text).foregroundStyle(.tint).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Searches for it.")
                }
            }
            .powerJackGlassCard()
        }
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
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let apply: (StudyOptions) -> Void
    @State private var customizing = false
    @State private var expanded: ExpandedGraph?
    @State private var editingReps = false
    @State private var editingDates = false
    @Environment(\.colorScheme) private var scheme
    /// Charts grow with the reader's text size so axis labels never crowd.
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 290

    var body: some View {
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
                StudyReadingGuide(study: study)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle("Chart").navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: isFavorite ? "star.fill" : "star", action: toggleFavorite)
                    .accessibilityIdentifier("data.detail.favorite")
                if let saveSearchView {
                    Menu {
                        Button("Save as default chart view", action: saveSearchView)
                    } label: { Label("Chart actions", systemImage: "ellipsis.circle") }
                }
                if study.question == nil {
                    Button("Customize chart", systemImage: "slider.horizontal.3") { customizing = true }
                }
            }
        }
        .sheet(isPresented: $customizing) {
            StudyCustomizationView(id: study.id, history: history, apply: apply, draft: options)
        }
        .fullScreenCover(item: $expanded) { graph in StudyFullscreenView(study: graph.study, title: graph.title) }
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
        let view = StudyFigureView(study: study, compact: false) { panel, title in
            expanded = ExpandedGraph(study: panel, title: title)
        }
        if hasSingleFigure {
            HStack {
                Spacer()
                ExpandChartButton(title: study.displayTitle) {
                    expanded = ExpandedGraph(study: study, title: study.displayTitle)
                }
            }
            .padding(.bottom, -18)
        }
        switch study.figure {
        case .traces(let series, _):
            view.frame(height: chartHeight)
            legend(series.map(\.name))
        case .bars(let bars):
            if study.horizontalCategories {
                // Every row keeps its height. Past twelve the chart scrolls inside the card.
                let rows = bars.map(\.label).studyUnique
                let row = StudyCategoryPlot.rowHeight(labels: rows)
                if rows.count > StudyCategoryPlot.visibleRows {
                    ScrollView { view.frame(height: StudyCategoryPlot.height(labels: rows)) }
                        .frame(height: CGFloat(StudyCategoryPlot.visibleRows) * row + 44)
                } else {
                    view.frame(height: StudyCategoryPlot.height(labels: rows))
                }
            } else {
                view.frame(height: chartHeight - 20)
            }
            let labels = bars.reduce(into: [String]()) {
                if !$1.group.isEmpty && !$0.contains($1.group) { $0.append($1.group) }
            }
            if !labels.isEmpty { legend(labels) }
        case .comparison(let points, _):
            view.frame(height: max(160, CGFloat(Set(points.map(\.category)).count) * 54))
            legend(points.map(\.series).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } })
        case .matrix:
            view
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

    /// Each graph opens on its own: one lift panel, or the study's single figure.
    private struct ExpandedGraph: Identifiable {
        let study: StudyResult
        let title: String
        var id: String { title }
    }

    /// Lift panels carry an expand control per lift. Every other figure has one for the whole graph.
    private var hasSingleFigure: Bool {
        switch study.figure {
        case .liftPanels, nil: false
        default: true
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
    let container = store.container!
    let seeded = Result { try SimulatorTrainingHistory.populate(in: container.mainContext) }

    switch seeded {
    case .success:
        ProgramDataView()
            .modelContainer(container)
    case .failure(let error):
        ContentUnavailableView {
            Label("Sample history unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        }
    }
}
#endif
