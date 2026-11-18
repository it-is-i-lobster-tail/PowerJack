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

    /// The navigation bar's buttons are glass circles this wide, set in from the screen's edges
    /// by the system margin (see `onBarButtonInsetChange`). The floating bottom bar lines up with them.
    static let barButtonSize: CGFloat = 44
}
