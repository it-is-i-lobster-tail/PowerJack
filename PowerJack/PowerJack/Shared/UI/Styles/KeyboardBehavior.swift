//
//  KeyboardBehavior.swift
//  PowerJack
//
//  One keyboard behavior for every screen with text or number input.
//

import SwiftUI
import UIKit

extension View {
    /// The keyboard slides over bottom bars instead of pushing them up,
    /// and tapping anywhere outside a text field closes it and clears focus.
    /// Apply once at the root; it covers pushed screens and sheets too.
    func powerJackKeyboardBehavior() -> some View {
        ignoresSafeArea(.keyboard, edges: .bottom)
            .background(TapOutsideEndsEditing())
    }
}

/// Adds a window-wide tap recognizer that ends editing without blocking other taps.
private struct TapOutsideEndsEditing: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            recognizer.view?.endEditing(true)
        }

        // Taps on a text field move focus there instead of closing the keyboard.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
