import SwiftUI

/// A blue info icon and one short line, shown above or below a form's cards.
struct FormInfoNote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
            Spacer()
        }
    }
}
