//
//  LayoutMetrics.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

enum LayoutMetrics {
    static let compactSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 20

    static let compactCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 14
    static let curvedCornerRaius: CGFloat = 28

    /// Where the navigation bar puts its buttons: glass circles this far in from the screen's edges.
    /// The floating bottom bar lines up with them, so the two bars share one left and one right edge.
    static let barButtonInset: CGFloat = 16
    static let barButtonSize: CGFloat = 44
    /// The center line of the navigation bar's leading button (the back button).
    static let barButtonCenterInset: CGFloat = barButtonInset + barButtonSize / 2
}
