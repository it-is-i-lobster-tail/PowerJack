//
//  GlassFormScaffold.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct GlassFormScaffold<Fields: View, Footer: View>: View {
    let navigationTitle: LocalizedStringKey
    let headerSystemImage: String
    let headerTitle: LocalizedStringKey

    private let fields: () -> Fields
    private let footer: () -> Footer

    init(
        navigationTitle: LocalizedStringKey,
        headerSystemImage: String,
        headerTitle: LocalizedStringKey,
        @ViewBuilder fields: @escaping () -> Fields,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.navigationTitle = navigationTitle
        self.headerSystemImage = headerSystemImage
        self.headerTitle = headerTitle
        self.fields = fields
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.sectionSpacing) {
            ScrollView {
                // Inside the scroll view, so glass cards are clipped when they scroll
                // under the title or the footer instead of drawing over them.
                GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
                    VStack(spacing: LayoutMetrics.sectionSpacing) {
                        GlassFormHeader(
                            systemImage: headerSystemImage,
                            title: headerTitle
                        )
                        fields()
                    }
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)
                }
            }

            footer()
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .padding(.vertical, LayoutMetrics.sectionSpacing)
        .background(Color(uiColor: .systemBackground))
        .keyboardSlidesOver()
    }
}

private struct GlassFormHeader: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
            Text(title)
                .font(.caption)
            Spacer()
        }
    }
}
