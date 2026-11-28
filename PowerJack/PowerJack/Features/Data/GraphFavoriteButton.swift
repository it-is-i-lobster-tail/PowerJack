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

/// A small star beside one graph's title. Filled when that graph is a favorite.
struct GraphFavoriteButton: View {
    let title: String
    let isFavorite: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.body.weight(.semibold))
                .symbolEffect(.bounce, value: isFavorite)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        // Keep the title row its own height. The tap area still reaches 44 points.
        .padding(.vertical, -11)
        .padding(.trailing, -12)
        .accessibilityLabel(isFavorite ? "Remove \(title) from Favorites" : "Favorite \(title)")
        .sensoryFeedback(.selection, trigger: isFavorite)
    }
}
