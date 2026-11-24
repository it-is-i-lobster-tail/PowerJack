import SwiftUI

/// Checkable choices with an empty selection representing every option.
struct FilterOptions<Option: Identifiable & Hashable>: View {
    let allTitle: String
    let choices: [Option]
    @Binding var selected: Set<Option>
    let title: (Option) -> String

    init(_ allTitle: String, choices: [Option], selected: Binding<Set<Option>>, title: @escaping (Option) -> String) {
        self.allTitle = allTitle
        self.choices = choices
        self._selected = selected
        self.title = title
    }

    var body: some View {
        Section {
            filterOption(allTitle, isSelected: selected.isEmpty) {
                selected.removeAll()
            }
        }
        Section {
            ForEach(choices) { option in
                filterOption(title(option), isSelected: selected.contains(option)) {
                    if selected.remove(option) == nil { selected.insert(option) }
                }
            }
        }
    }

    private func filterOption(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
