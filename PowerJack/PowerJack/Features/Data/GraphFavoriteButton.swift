import SwiftUI

/// Lets a page that shows several graphs star just one of them.
struct GraphFavorites: Equatable {
    /// The lifts whose own graph is already a favorite.
    let starred: Set<String>
    let toggle: (_ exerciseKey: String, _ title: String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.starred == rhs.starred }
}

extension StudyResult {
    /// The lifts shown as graphs of their own on this page.
    var graphKeys: [String] {
        guard case .liftPanels(let series) = figure else { return [] }
        return series.compactMap(\.exerciseKey)
    }
}

extension EnvironmentValues {
    @Entry var graphFavorites: GraphFavorites?
}

/// A star on one graph's title row, styled like its expand control. Filled when that graph is a favorite.
struct GraphFavoriteButton: View {
    let title: String
    let key: String
    let favorites: GraphFavorites

    private var isFavorite: Bool { favorites.starred.contains(key) }

    var body: some View {
        Button { favorites.toggle(key, title) } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.subheadline)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: isFavorite)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites" : "Favorite \(title)")
        .accessibilityIdentifier("data.graph.favorite.\(key)")
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}
