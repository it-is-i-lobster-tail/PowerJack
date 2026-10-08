//
//  FAQView.swift
//  PowerJack
//

import SwiftUI

// Questions grouped by topic. Tapping a question opens its answer below it.
// A ScrollView rather than a List: a List cell jumps to its new height and re-centers
// the question, so the question can't stay put while the answer opens.
struct FAQView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                ForEach(FAQ.topics, id: \.self) { topic in
                    FAQSection(topic: topic)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FAQSection: View {
    let topic: FAQ.Topic

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Text(topic.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(topic.entries, id: \.self) { entry in
                    if entry != topic.entries.first {
                        Divider().padding(.leading)
                    }
                    FAQRow(entry: entry)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: LayoutMetrics.curvedCornerRaius))
        }
    }
}

private struct FAQRow: View {
    let entry: FAQ.Entry

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.45)) {
                    isExpanded.toggle()
                }
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
                .padding()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the answer" : "Shows the answer")

            // Always laid out and pinned to the top, so the open animates its height
            // down from the question instead of popping in.
            FAQAnswer(entry: entry)
                .padding([.horizontal, .bottom])
                .frame(height: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .accessibilityHidden(!isExpanded)
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
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("FAQ") {
    NavigationStack {
        FAQView()
    }
}
