//
//  GlassSurfaceStyle.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

extension View {
    func powerJackGlassCard(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.white.opacity(VisualOpacity.standard))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius)
        )
    }

    func powerJackGlassPanel() -> some View {
        glassEffect(
            .regular.tint(.white.opacity(VisualOpacity.subtle)),
            in: .rect(cornerRadius: LayoutMetrics.panelCornerRadius)
        )
    }
}
