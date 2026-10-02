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
    @State private var router = ProgramsRouter()

    init(
        modelContainer: ModelContainer,
        @ViewBuilder content: () -> Content
    ) {
        self.modelContainer = modelContainer
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .programRouteDestinations()
        }
        .environment(router)
        .modelContainer(modelContainer)
    }
}
