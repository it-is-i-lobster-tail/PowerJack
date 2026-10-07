//
//  Hint.swift
//  PowerJack
//
//  Short, dismissible tips built on TipKit. The Hints switch in Settings turns them all off.
//
//  To add a hint:
//  1. Declare it next to its feature: `struct MyHint: Hint { var title: Text { Text("…") } }`.
//  2. Show it with `.popoverHint(MyHint())` on the control it explains, or `HintView(MyHint())` inline.
//  3. Call `MyHint().invalidate(reason: .actionPerformed)` once the lifter has done what it teaches.
//  Each hint shows until it's closed or invalidated. Give it an `occasion` to show it again later.
//

import SwiftUI
import TipKit

// Nonisolated because TipKit reads hints off the main actor.
nonisolated protocol Hint: Tip {
    /// Shows the hint again on each new occasion. Nil shows it once.
    var occasion: HintOccasion? { get }
    /// Rules on top of the Hints switch, e.g. waiting for an event.
    var extraRules: [Rule] { get }
}

nonisolated extension Hint {
    var occasion: HintOccasion? { nil }
    var extraRules: [Rule] { [] }
    // Xcode 26 doesn't pick up TipKit's own defaults through this nonisolated protocol.
    var image: Image? { nil }
    var actions: [Action] { [] }
    var options: [any TipOption] { [] }

    var id: String {
        guard let occasion else { return "\(Self.self)" }
        return "\(Self.self).\(occasion.rawValue)"
    }

    var rules: [Rule] {
        [#Rule(Hints.$isEnabled) { $0 }] + extraRules
    }
}

nonisolated enum Hints {
    /// Mirrors the Hints switch in Settings, so turning it off hides any hint on screen.
    @Parameter static var isEnabled: Bool = AppSettings.Default.hints

    /// Call once at launch, before any hint view appears.
    static func configure() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Tips.hideAllTipsForTesting()
        }
        isEnabled = UserDefaults.standard.object(forKey: AppSettings.Key.hints) as? Bool ?? AppSettings.Default.hints
        try? Tips.configure()
    }
}

extension View {
    /// Points a hint at this view. The screen stays usable while it shows, so it never blocks a tap.
    func popoverHint(_ hint: (any Hint)?, arrowEdge: Edge = .top) -> some View {
        popoverTip(hint, arrowEdge: arrowEdge)
            .tipBackgroundInteraction(.enabled)
    }
}

/// A hint shown inline, taking up space in the layout.
struct HintView<Content: Hint>: View {
    let hint: Content

    init(_ hint: Content) {
        self.hint = hint
    }

    var body: some View {
        TipView(hint)
    }
}
