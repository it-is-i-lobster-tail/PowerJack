import SwiftUI

/// One graph alone in full screen: its title, Share and Close, and the graph filling the space.
/// Date charts zoom their own time axis with a pinch, so the page itself never scales.
struct StudyFullscreenView: View {
    let study: StudyResult
    let title: String
    /// Set when this lift came from a page of several graphs, so it can be starred on its own.
    var graphFavorites: GraphFavorites?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ExpandedChartPresentation(title: title, close: { dismiss() }, accessory: {
            if let graphFavorites, let key = study.graphKeys.first {
                GraphFavoriteButton(title: title, key: key, favorites: graphFavorites)
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                figure.modifier(ExportableChart())
                if study.legendLabels.count > 1 { legend }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var figure: some View {
        let view = StudyFigureView(study: study, compact: false, fillsScreen: true)
        switch study.figure {
        case .table(let table):
            ScrollView { StudyTableView(table: table) }
        case .matrix, .attempts:
            ScrollView([.horizontal, .vertical]) { view }
        case .bars(let bars) where study.horizontalCategories:
            ScrollView {
                view.frame(height: StudyCategoryPlot.height(categories: Set(bars.map(\.label)).count))
            }
        case .comparison(let points, _):
            GeometryReader { geometry in
                ScrollView {
                    view.frame(height: max(geometry.size.height, CGFloat(Set(points.map(\.category)).count) * 46))
                }
            }
        default:
            view.frame(maxHeight: .infinity)
        }
    }

    /// Colors only mean something with their names, so graphs with several series keep a one-line key.
    private var legend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(study.legendLabels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 6) {
                        Circle().fill(WorkoutChartPalette.color(at: index, scheme: scheme)).frame(width: 8, height: 8)
                        Text(label).font(.caption)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
