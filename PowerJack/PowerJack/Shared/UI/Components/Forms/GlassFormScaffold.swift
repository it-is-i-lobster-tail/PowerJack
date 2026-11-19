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
                // Inside the scroll view, so glass cards fade under the title instead of drawing over it.
                GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
                    VStack(spacing: LayoutMetrics.sectionSpacing) {
                        GlassFormHeader(
                            systemImage: headerSystemImage,
                            title: headerTitle
                        )
                        fields()
                    }
                    .padding([.horizontal, .top], LayoutMetrics.sectionSpacing)
                }
            }

            footer()
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
        }
        // The fields stop above the footer instead of running under the bar: a scroll view that
        // reaches the bottom edge scrolls a focused name field up under the title when the keyboard shows.
        .padding(.bottom, LayoutMetrics.sectionSpacing)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
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
