//
//  Hint.swift
//  PowerJack
//
//  Short, dismissible tips built on TipKit. The Hints switch in Settings turns them all off.
//
//  To add a hint:
//  1. Declare it next to its feature: `struct MyHint: Hint { var title: Text { Text("…") } }`.
//  2. Show it with `.popoverHint(MyHint())` on the control it explains, or `HintView(MyHint())` inline.
//     Inside a glass container, mark the control with `.hintAnchor("id")` and call
//     `.popoverHints(["id": MyHint()])` outside the container instead.
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
        background {
            Color.clear
                .popoverTip(hint, arrowEdge: arrowEdge)
                .tipBackgroundInteraction(.enabled)
                // A new hint replaces the popover; otherwise the old one's text stays on screen.
                .id(hint?.id)
        }
    }
}

extension View {
    /// Marks this view so `popoverHints(_:)` on an outer view can point a hint at it.
    /// Use it inside a `GlassEffectContainer`, where popovers don't present.
    func hintAnchor(_ id: String) -> some View {
        anchorPreference(key: HintAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Points each hint at the view inside this one marked with the same `hintAnchor(_:)` ID.
    func popoverHints(_ hints: [String: (any Hint)?], arrowEdge: Edge = .top) -> some View {
        overlayPreferenceValue(HintAnchorKey.self) { anchors in
            GeometryReader { proxy in
                ForEach(hints.keys.sorted(), id: \.self) { id in
                    if let hint = hints[id] ?? nil, let anchor = anchors[id] {
                        let frame = proxy[anchor]
                        Color.clear
                            .frame(width: frame.width, height: frame.height)
                            // Before position, so the popover points at the anchor, not the whole overlay.
                            .popoverHint(hint, arrowEdge: arrowEdge)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            // Taps go through to the marked view underneath.
            .allowsHitTesting(false)
        }
    }
}

private struct HintAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A hint shown inline, taking up space in the layout.
struct HintView: View {
    let hint: any Hint

    init(_ hint: any Hint) {
        self.hint = hint
    }

    var body: some View {
        TipView(hint)
    }
}
