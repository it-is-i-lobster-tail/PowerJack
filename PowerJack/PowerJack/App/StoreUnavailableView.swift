//
//  StoreUnavailableView.swift
//  PowerJack
//
//  Shown in place of the app when the training data won't open, for example before the first
//  unlock after a restart or when storage is full. The store's file is never touched.
//

import SwiftUI

struct StoreUnavailableView: View {
    @Environment(PowerJackStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("PowerJack couldn't open your training data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Nothing was deleted. Try again in a moment, or after freeing up some storage.")
        } actions: {
            Button("Try Again") { store.retryOpening() }
                .buttonStyle(.borderedProminent)
            shareDiagnostics
        }
        .traceScreen("Store unavailable")
    }

    /// The trace when it's on, otherwise just what went wrong. Neither holds names or training data.
    @ViewBuilder
    private var shareDiagnostics: some View {
        if TraceLog.shared.isEnabled {
            ShareLink(item: TraceArchive(traceLog: .shared), preview: SharePreview("PowerJack Diagnostics")) {
                Text("Share Diagnostics")
            }
        } else if let summary = store.openFailureSummary {
            ShareLink(item: summary) {
                Text("Share Diagnostics")
            }
        }
    }
}
