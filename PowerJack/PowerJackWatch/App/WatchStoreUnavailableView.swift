//
//  WatchStoreUnavailableView.swift
//  PowerJackWatch
//
//  Shown in place of the app when the watch's training data won't open. Its file is never touched.
//

import SwiftUI

struct WatchStoreUnavailableView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Couldn't open your training data")
                    .font(.headline)
                Text("Nothing was deleted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") { store.retryOpening() }
            }
            .multilineTextAlignment(.center)
        }
    }
}
