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
    /// Apply once at the root. Tab pages and the screens pushed inside them track
    /// the keyboard on their own, so they also need `powerJackTabPage` and `keyboardSlidesOver()`.
    func powerJackKeyboardBehavior() -> some View {
        ignoresSafeArea(.keyboard, edges: .bottom)
            .background(TapOutsideEndsEditing())
    }

    /// Lays out one page of the root TabView: it stops above the floating bottom bar,
    /// and the keyboard slides over the page instead of squeezing it.
    func powerJackTabPage(bottomBarHeight: CGFloat) -> some View {
        padding(.bottom, bottomBarHeight)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// The keyboard slides over this screen instead of squeezing it, so bottom content
    /// like the exercise strip or a Save button stays put behind the keyboard.
    /// Use it on screens with text input that are pushed inside a tab.
    func keyboardSlidesOver() -> some View {
        ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Keeps the focused row of a scroll view in sight above a keyboard that slides over it.
    /// The scroll view gains room at the bottom as tall as the part the keyboard covers,
    /// and scrolls the row with `focusedID` up into the part still showing.
    /// Apply to the ScrollView; each row needs a matching `.id(_:)`.
    func keepsFocusAboveKeyboard(_ focusedID: (some Hashable)?) -> some View {
        modifier(KeepsFocusAboveKeyboard(focusedID: focusedID))
    }
}

private struct KeepsFocusAboveKeyboard<ID: Hashable>: ViewModifier {
    let focusedID: ID?

    @State private var bottomEdge: CGFloat = 0
    @State private var keyboardTop: CGFloat = .infinity

    /// How much of the scroll view the keyboard covers.
    private var coveredHeight: CGFloat {
        max(0, bottomEdge - keyboardTop)
    }

    /// The covered part plus a small gap, so the focused row doesn't sit flush on the keyboard.
    private var bottomRoom: CGFloat {
        coveredHeight > 0 ? coveredHeight + LayoutMetrics.compactSpacing : 0
    }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .safeAreaPadding(.bottom, bottomRoom)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottomEdge = $0 }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                    keyboardTop = frame.minY
                }
                // Focus changes before the keyboard reports its frame, so scroll after either one.
                .onChange(of: focusedID) { scrollToFocus(proxy) }
                .onChange(of: coveredHeight) { scrollToFocus(proxy) }
        }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let focusedID, coveredHeight > 0 else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(focusedID)
        }
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
