import SwiftUI
import Testing
import UIKit
@testable import PowerJack

/// The number pad must slide over the bottom of the screen, never squeeze it and push
/// content like the exercise strip up. A screen pushed inside a tab is hosted twice
/// (the tab page, then the pushed screen), and each host shrinks for the keyboard
/// unless it opts out, so the app needs both `powerJackTabPage` and `keyboardSlidesOver()`.
/// These checks use the real number pad in the same hosting the app uses.
@MainActor
@Suite(.serialized)
struct KeyboardLayoutTests {
    @Test func screenWithBothOptOutsIsNotSqueezed() async throws {
        let bottom = try await bottomEdgeAroundNumberPad(tabPage: .powerJackTabPage, screen: true)
        #expect(bottom.after >= bottom.before)
    }

    @Test func screenWithoutKeyboardSlidesOverIsSqueezed() async throws {
        let bottom = try await bottomEdgeAroundNumberPad(tabPage: .powerJackTabPage, screen: false)
        #expect(bottom.after < bottom.before)
    }

    @Test func tabPageWithOnlyPaddingIsSqueezed() async throws {
        let bottom = try await bottomEdgeAroundNumberPad(tabPage: .paddingOnly, screen: true)
        #expect(bottom.after < bottom.before)
    }

    @Test func tabPageStopsAboveTheBottomBar() async throws {
        let bottom = try await bottomEdgeAroundNumberPad(tabPage: .powerJackTabPage, screen: true, showNumberPad: false)
        let withoutBar = try await bottomEdgeAroundNumberPad(tabPage: .none, screen: true, showNumberPad: false)
        #expect(bottom.before == withoutBar.before - Self.barHeight)
    }

    private static let barHeight: CGFloat = 60

    /// The bottom edge of a pushed screen's content before and after the number pad appears.
    private func bottomEdgeAroundNumberPad(
        tabPage: TabPageLayout,
        screen optsOut: Bool,
        showNumberPad: Bool = true
    ) async throws -> (before: CGFloat, after: CGFloat) {
        let probe = BottomEdgeProbe()
        let screen = try await ScreenUnderTest(
            TabView {
                Tab {
                    NavigationStack {
                        Color.clear.navigationDestination(isPresented: .constant(true)) {
                            ProbeScreen(probe: probe, optsOut: optsOut)
                        }
                    }
                    .modifier(TabPage(layout: tabPage, bottomBarHeight: Self.barHeight))
                }
            }
            .powerJackKeyboardBehavior()
        )
        defer { screen.close() }
        let before = probe.bottom
        if showNumberPad {
            try await screen.showNumberPad()
        }
        #expect(before > 0)
        return (before, probe.bottom)
    }
}

// MARK: - Helpers

/// Shows a view full screen in the test host's window and lets it settle.
@MainActor
private final class ScreenUnderTest {
    private let window: UIWindow
    private var field: UITextField?

    init(_ view: some View) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(1))
    }

    /// Brings up the real number pad, the same keyboard the Weight and Reps fields use.
    func showNumberPad() async throws {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        field.keyboardType = .decimalPad
        window.addSubview(field)
        self.field = field

        var didShow = false
        let token = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { didShow = true }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        field.becomeFirstResponder()
        for _ in 0..<30 where !didShow {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(didShow, "The software keyboard didn't appear. Turn off Simulator > I/O > Keyboard > Connect Hardware Keyboard.")
        try await Task.sleep(for: .milliseconds(500))
    }

    func close() {
        field?.resignFirstResponder()
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class BottomEdgeProbe {
    var bottom: CGFloat = 0
}

/// Stands in for a screen like the workout: its content fills the space it's given.
private struct ProbeScreen: View {
    let probe: BottomEdgeProbe
    let optsOut: Bool

    var body: some View {
        let content = Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { probe.bottom = $0 }
        if optsOut {
            content.keyboardSlidesOver()
        } else {
            content
        }
    }
}

private enum TabPageLayout {
    case none
    /// Room for the bar without opting out of the keyboard: the bug this suite guards against.
    case paddingOnly
    case powerJackTabPage
}

private struct TabPage: ViewModifier {
    let layout: TabPageLayout
    let bottomBarHeight: CGFloat

    func body(content: Content) -> some View {
        switch layout {
        case .none:
            content
        case .paddingOnly:
            content.padding(.bottom, bottomBarHeight)
        case .powerJackTabPage:
            content.powerJackTabPage(bottomBarHeight: bottomBarHeight)
        }
    }
}
