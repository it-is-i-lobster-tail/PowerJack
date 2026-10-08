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
    /// Called on every tap, including a tap on the option that's already selected.
    var onTap: (Option) -> Void = { _ in }

    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy) {
                        selection = option
                    }
                    onTap(option)
                } label: {
                    Text(title(option))
                        .font(.default)
                        .fontWeight(.regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        // The whole pill is tappable, not just the letters.
                        .contentShape(Capsule())
                        .background {
                            if selection == option {
                                Color.clear
                                    .glassEffect(.regular, in: Capsule())
                                    .matchedGeometryEffect(
                                        id: "selection",
                                        in: animation
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                // Lets an outer view point a hint at this option.
                .hintAnchor(String(describing: option.id))
            }
        }
        .padding(4)
        .powerJackGlassSelection()
        .onChange(of: options) { _, newOptions in
            if !newOptions.contains(selection),
               let first = newOptions.first {
                selection = first
            }
        }
    }
}
