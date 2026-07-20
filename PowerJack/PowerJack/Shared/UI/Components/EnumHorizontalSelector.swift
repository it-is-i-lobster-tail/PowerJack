//
//  EnumHorizontalSelector.swift
//  PowerJack
//
//  Created by trogdor on 7/15/26.
//

import SwiftUI

protocol EnumHorizontalSelectorOption:
    CaseIterable,
    Hashable,
    RawRepresentable
where RawValue == Int {

    var label: String { get }
}

struct EnumHorizontalSelector<Option: EnumHorizontalSelectorOption>: View {
    @Binding var selection: Option?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    VStack {
                        Text(option.rawValue, format: .number)
                            .font(.default)
                        Text(option.label)
                            .font(.caption2)
                            .lineLimit(1)
                            .allowsTightening(true)
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, minHeight: 60, idealHeight: 80)
                .background(
                    Color.secondary.opacity(
                        isSelected
                        ? VisualOpacity.standard
                        : VisualOpacity.subtle
                    ),
                    in: RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)
                )
            }
        }
    }
}
