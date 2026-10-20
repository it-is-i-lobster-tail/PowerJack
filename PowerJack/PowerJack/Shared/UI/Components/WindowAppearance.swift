//
//  WindowAppearance.swift
//  PowerJack
//
//  Sets light or dark on the whole window, so open sheets switch too.
//  `preferredColorScheme(nil)` leaves an open sheet in the old style.
//

import SwiftUI
import UIKit

extension View {
    func windowAppearance(_ appearance: Appearance) -> some View {
        background(WindowAppearance(style: appearance.userInterfaceStyle))
    }
}

private struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> StyleView {
        StyleView()
    }

    func updateUIView(_ view: StyleView, context: Context) {
        view.style = style
    }

    final class StyleView: UIView {
        var style = UIUserInterfaceStyle.unspecified {
            didSet { window?.overrideUserInterfaceStyle = style }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.overrideUserInterfaceStyle = style
        }
    }
}
