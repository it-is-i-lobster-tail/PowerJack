//
//  SlidingGlassPicker.swift
//  PowerJack
//
//  Created by trogdor on 7/22/26.
//

import SwiftUI

struct BrowserOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let index: Int
}

struct SlidingGlassPicker<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.default)
                        .fontWeight(.regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if selection == option {
                                Color.clear
                                    .glassEffect(
                                        .regular.interactive(),
                                        in: Capsule()
                                    )
                                    .matchedGeometryEffect(
                                        id: "selection",
                                        in: animation
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .powerJackGlassSelection(interactive: true)
        .onChange(of: options) { _, newOptions in
            if !newOptions.contains(selection),
               let first = newOptions.first {
                selection = first
            }
        }
    }
}
