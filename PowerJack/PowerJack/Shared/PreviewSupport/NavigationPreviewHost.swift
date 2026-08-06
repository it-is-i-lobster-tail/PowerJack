//
//  NavigationPreviewHost.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftData
import SwiftUI

/// Provides navigation and SwiftData dependencies for previews.
struct NavigationPreviewHost<Content: View>: View {
    private let modelContainer: ModelContainer
    private let content: Content

    init(
        modelContainer: ModelContainer,
        @ViewBuilder content: () -> Content
    ) {
        self.modelContainer = modelContainer
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .modelContainer(modelContainer)
    }
}
