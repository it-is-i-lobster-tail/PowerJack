//
//  EdgeBlur.swift
//  PowerJack
//
//  Softens content that scrolls under a floating bar.
//

import SwiftUI

/// Softens content that scrolls under a floating bar, like the scroll edge effect under a title:
/// clear where content first meets the bar, blurring and fading into the page toward the screen's edge.
/// At rest, content ends before it.
struct EdgeBlur: View {
    /// The screen edge the bar sits on.
    let edge: VerticalEdge

    private static let fade = Gradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.3),
    ])

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // The material alone is lighter than a dark page, so fade it toward the page color.
            .overlay(Color(uiColor: .systemBackground).opacity(0.7))
            .mask(
                LinearGradient(
                    gradient: Self.fade,
                    startPoint: edge == .top ? .bottom : .top,
                    endPoint: edge == .top ? .top : .bottom
                )
            )
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
