//
//  ScaleSelector.swift
//  PowerJack
//
//  Created by trogdor on 7/15/26.
//

import SwiftUI

protocol ScaleSelectorOption:
    CaseIterable,
    Hashable,
    RawRepresentable
where RawValue == Int {

    var label: String { get }
}

/// A 0–5 style rating laid out as a grid so every label fits on any iPhone.
struct ScaleSelector<Option: ScaleSelectorOption>: View {
    @Binding var selection: Option?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: LayoutMetrics.compactSpacing),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: LayoutMetrics.compactSpacing) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 2) {
                        Text(option.rawValue, format: .number)
                            .font(.title3.weight(.semibold))
                        Text(option.label)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        isSelected ? Color.accentColor : Color(uiColor: .secondarySystemFill),
                        in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
