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
    
    /// The floating section switcher's glass.
    func powerJackGlassSelection(interactive: Bool = false) -> some View {
        glassEffect(
            Glass.powerJackBar.interactive(interactive),
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

extension Glass {
    /// The bars' see-through gray, like Safari's tab bar, so the page bleeds through.
    static let powerJackBar = Glass.regular.tint(Color(uiColor: .systemGray).opacity(0.3))
}
