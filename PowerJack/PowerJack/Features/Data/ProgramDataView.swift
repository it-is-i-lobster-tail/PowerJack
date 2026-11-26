import SwiftData
import SwiftUI

struct ProgramDataView: View {
    @Query private var programs: [Program]
    @Query private var logs: [WorkoutLog]
    @Query private var archived: [HistoryRecord]
    @Query private var imported: [ImportedSet]
    @Query private var exercises: [Exercise]
    @AppStorage(AppSettings.Key.weightUnit) private var unit = WeightUnit.current

    var body: some View {
        let history = StudyHistory(
            programs: programs, archive: archived, logs: logs, imported: imported, exercises: exercises, unit: unit)
        StudyGallery(history: history)
    }
}

private struct StudyGallery: View {
    let history: StudyHistory
    @AppStorage(SavedStudyViews.storageKey) private var storedOptions = Data()

    private func save(_ options: StudyOptions, for id: TrainingStudy) {
        if let data = try? SavedStudyViews(data: storedOptions).saving(options, for: id) {
            storedOptions = data
        }
    }
    @Namespace private var zoom
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: 2)

    var body: some View {
        let choices = SavedStudyViews(data: storedOptions)
        return NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(TrainingStudy.allCases) { id in
                        let options = choices[id]
                        let study = history.result(for: id, options: options)
                            .presented(as: options.presentation, transpose: options.transpose)
                        NavigationLink(value: study.id) {
                            VStack(alignment: .leading, spacing: 7) {
                                StudyThumbnail(study: study)
                                    .aspectRatio(1.65, contentMode: .fit)
                                    .powerJackGlassCard()
                                    .matchedTransitionSource(id: study.id, in: zoom)
                                Text(study.galleryCaption)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(study.galleryAccessibilityLabel)
                        .accessibilityHint(
                            study.figure == nil ? "No matching history. Opens chart details." : "Opens full-size chart."
                        )
                        .accessibilityIdentifier("data.study.\(study.id.rawValue)")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
            }
            .navigationTitle("Data")
            .navigationDestination(for: TrainingStudy.self) { id in
                let options = choices[id]
                let study = history.result(for: id, options: options)
                    .presented(as: options.presentation, transpose: options.transpose)
                StudyDetail(study: study, history: history, options: options, apply: { save($0, for: id) })
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
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
    let history: StudyHistory
    let options: StudyOptions
    let apply: (StudyOptions) -> Void
    @State private var customizing = false
    @State private var fullscreen = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(study.displayTitle).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(study.scope).font(.subheadline).foregroundStyle(.secondary)
                    chart
                    if !study.summary.isEmpty { Text(study.summary).font(.body) }
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
                Button("Customize chart", systemImage: "slider.horizontal.3") { customizing = true }
                Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { fullscreen = true }
            }
        }
        .sheet(isPresented: $customizing) {
            StudyCustomizationView(id: study.id, history: history, apply: apply, draft: options)
        }
        .fullScreenCover(isPresented: $fullscreen) { StudyFullscreenView(study: study, title: study.displayTitle) }
        .accessibilityIdentifier("data.detail.\(study.id.rawValue)")
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
