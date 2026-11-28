//
//  UnsavedChangesBanner.swift
//  PowerJack
//
//  A small note at the top of the screen while saves keep failing. It never blocks a tap.
//

import SwiftUI

struct UnsavedChangesBanner: View {
    private var health = SaveHealth.shared

    var body: some View {
        ZStack {
            if health.changesAreUnsaved {
                Label("Your last changes aren't saved yet", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, LayoutMetrics.compactSpacing)
                    .glassEffect(.regular.tint(.orange.opacity(VisualOpacity.subtle)), in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Just under the navigation bar's buttons, so it never hides them.
        .padding(.top, LayoutMetrics.barButtonSize + LayoutMetrics.compactSpacing)
        .allowsHitTesting(false)
        .animation(.snappy, value: health.changesAreUnsaved)
    }
}
