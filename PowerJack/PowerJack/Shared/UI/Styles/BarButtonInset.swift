//
//  BarButtonInset.swift
//  PowerJack
//
//  How far in from the screen's edges the navigation bar puts its buttons,
//  so the floating bottom bar can line up with them on every iPhone.
//

import SwiftUI
import UIKit

extension View {
    /// Reports the inset UIKit gives the navigation bar's buttons: the system's minimum
    /// side margin, 16pt on most iPhones and 20pt on the widest. Called again only if it changes.
    func onBarButtonInsetChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(SystemMarginReader(onChange: action))
    }
}

private struct SystemMarginReader: UIViewControllerRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onChange = onChange
    }

    final class Controller: UIViewController {
        var onChange: (CGFloat) -> Void = { _ in }
        private var reportedInset: CGFloat?

        // Called before the first frame shows, so the bar never jumps on launch.
        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            report()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            report()
        }

        private func report() {
            guard let inset = view.window?.rootViewController?.systemMinimumLayoutMargins.leading,
                  inset != reportedInset else { return }
            reportedInset = inset
            onChange(inset)
        }
    }
}
