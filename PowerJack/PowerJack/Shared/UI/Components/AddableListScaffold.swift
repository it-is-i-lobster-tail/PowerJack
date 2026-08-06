//
//  AddableListScaffold.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct AddableListScaffold<Content: View, CreateDestination: View>: View {
    let navigationTitle: LocalizedStringKey
    let isEmpty: Bool
    let emptyTitle: LocalizedStringKey
    let emptySystemImage: String

    private let content: () -> Content
    private let createDestination: () -> CreateDestination

    @State private var isCreating = false

    init(
        navigationTitle: LocalizedStringKey,
        isEmpty: Bool,
        emptyTitle: LocalizedStringKey,
        emptySystemImage: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder createDestination: @escaping () -> CreateDestination
    ) {
        self.navigationTitle = navigationTitle
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.content = content
        self.createDestination = createDestination
    }

    var body: some View {
        content()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isCreating) {
                createDestination()
            }
            .overlay {
                if isEmpty {
                    EmptyStateView(
                        title: emptyTitle,
                        systemImage: emptySystemImage
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: presentCreateDestination) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
    }

    private func presentCreateDestination() {
        isCreating = true
    }
}
