//
//  GlassPickerField.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct GlassPickerField<Option: Hashable, Label: View, OptionLabel: View>: View {
    let options: [Option]
    let height: CGFloat

    @Binding var selection: Option?

    private let label: () -> Label
    private let optionLabel: (Option) -> OptionLabel

    init(
        selection: Binding<Option?>,
        options: [Option],
        height: CGFloat = 55,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder optionLabel: @escaping (Option) -> OptionLabel
    ) {
        _selection = selection
        self.options = options
        self.height = height
        self.label = label
        self.optionLabel = optionLabel
    }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options, id: \.self) { option in
                optionLabel(option)
                    .tag(option as Option?)
            }
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .pickerStyle(.navigationLink)
        .padding(.vertical, LayoutMetrics.sectionSpacing)
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .powerJackGlassCard(interactive: true)
    }
}

struct FormFieldLabel: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
