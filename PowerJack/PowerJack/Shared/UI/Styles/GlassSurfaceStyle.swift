//
//  GlassSurfaceStyle.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

extension Color {
    /// Glass tint that follows the system theme: white in light mode, black in dark mode.
    static let glassSurface = Color(uiColor: .systemBackground)
}

extension View {
    func powerJackGlassCard(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.standard))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius)
        )
    }

    func powerJackGlassPanel() -> some View {
        glassEffect(
            .regular.tint(.glassSurface.opacity(VisualOpacity.subtle)),
            in: .rect(cornerRadius: LayoutMetrics.panelCornerRadius)
        )
    }
    
    func powerJackGlassSelection(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.heavy))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.curvedCornerRaius)
        )
    }

    /// Matches `powerJackGlassSelection` for round buttons that sit beside it.
    func powerJackGlassCircle(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.heavy))
                .interactive(interactive),
            in: .circle
        )
    }
}
