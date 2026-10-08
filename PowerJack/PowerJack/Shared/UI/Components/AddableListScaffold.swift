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
    let hint: (any Hint)?

    private let content: () -> Content
    private let createDestination: () -> CreateDestination
    private let onAdd: (() -> Void)?

    @State private var isCreating = false

    init(
        navigationTitle: LocalizedStringKey,
        isEmpty: Bool,
        emptyTitle: LocalizedStringKey,
        emptySystemImage: String,
        hint: (any Hint)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder createDestination: @escaping () -> CreateDestination
    ) {
        self.navigationTitle = navigationTitle
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.hint = hint
        self.content = content
        self.createDestination = createDestination
        self.onAdd = nil
    }

    var body: some View {
        content()
            .safeAreaInset(edge: .top, spacing: 0) {
                if let hint {
                    HintView(hint)
                        .padding(.horizontal)
                        .padding(.bottom, LayoutMetrics.compactSpacing)
                }
            }
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
        if let onAdd {
            onAdd()
        } else {
            isCreating = true
        }
    }
}

extension AddableListScaffold where CreateDestination == EmptyView {
    /// Use when the caller owns navigation, e.g. through a router path.
    init(
        navigationTitle: LocalizedStringKey,
        isEmpty: Bool,
        emptyTitle: LocalizedStringKey,
        emptySystemImage: String,
        hint: (any Hint)? = nil,
        onAdd: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.navigationTitle = navigationTitle
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.hint = hint
        self.content = content
        self.createDestination = { EmptyView() }
        self.onAdd = onAdd
    }
}
