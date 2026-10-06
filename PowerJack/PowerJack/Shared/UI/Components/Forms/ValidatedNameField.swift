//
//  ValidatedNameField.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct ValidatedNameField: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let maximumLength: Int
    let height: CGFloat

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    private var isOverLimit: Bool {
        text.count > maximumLength
    }

    private var showsCharacterCount: Bool {
        text.count >= Int((Double(maximumLength) * 0.8).rounded())
    }

    private var fieldTint: Color {
        if isOverLimit {
            return .red.opacity(VisualOpacity.light)
        }

        if isFocused {
            return .gray.opacity(VisualOpacity.light)
        }

        return .glassSurface.opacity(VisualOpacity.subtle)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil")
                .font(.title)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                    if showsCharacterCount {
                        Text("\(text.count)/\(maximumLength)")
                            .foregroundStyle(isOverLimit ? .red : .primary)
                    }
                    Spacer()
                }

                TextField(prompt, text: $text)
                    .focused($isFocused)
                    .padding(.horizontal, 13)
                    .padding(.vertical, LayoutMetrics.compactSpacing)
                    .glassEffect(
                        .regular
                            .tint(fieldTint)
                            .interactive(),
                        in: .rect(cornerRadius: LayoutMetrics.compactCornerRadius)
                    )
                    .animation(.easeOut(duration: 0.10), value: isFocused)
                    .animation(.easeOut(duration: 0.25), value: text)
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .padding(.vertical, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .powerJackGlassCard()
    }
}
