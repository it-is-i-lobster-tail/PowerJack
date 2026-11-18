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
    
    /// The floating section switcher's glass: a see-through gray, like Safari's tab bar, so the page bleeds through.
    func powerJackGlassSelection(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(Color(uiColor: .systemGray).opacity(0.3))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.curvedCornerRaius)
        )
    }

    /// Clear glass for round buttons beside the switcher, like Safari's + button.
    func powerJackGlassCircle(interactive: Bool = false) -> some View {
        glassEffect(
            .regular.interactive(interactive),
            in: .circle
        )
    }
}
