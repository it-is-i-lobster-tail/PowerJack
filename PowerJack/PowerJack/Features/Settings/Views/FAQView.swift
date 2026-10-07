//
//  FAQView.swift
//  PowerJack
//

import SwiftUI

// Questions grouped by topic. Tapping a question shows its answer right below it.
struct FAQView: View {
    var body: some View {
        List {
            ForEach(FAQ.topics, id: \.self) { topic in
                Section(topic.title) {
                    ForEach(topic.entries, id: \.self) { entry in
                        FAQRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FAQRow: View {
    let entry: FAQ.Entry

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(entry.question)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the answer" : "Shows the answer")

            if isExpanded {
                FAQAnswer(entry: entry)
            }
        }
    }
}

private struct FAQAnswer: View {
    let entry: FAQ.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            ForEach(entry.paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !entry.sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources")
                        .font(.footnote.weight(.semibold))
                    ForEach(entry.sources, id: \.self) { source in
                        Link(destination: source.url) {
                            Text(source.title)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.footnote)
                    }
                }
                // Borderless keeps each link its own tap target inside the list row.
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("FAQ") {
    NavigationStack {
        FAQView()
    }
}
