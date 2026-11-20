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
        let bottom = try await bottomEdgeAroundNumberPad(screen: true)
        #expect(bottom.after >= bottom.before)
    }

    @Test func screenWithoutKeyboardSlidesOverIsSqueezed() async throws {
        let bottom = try await bottomEdgeAroundNumberPad(screen: false)
        #expect(bottom.after < bottom.before)
    }

    @Test func nativeTabBarStaysBelowTheNumberPad() async throws {
        let edges = try await bottomEdgeAroundNumberPad(screen: true, measureTabBar: true)
        let keyboardTop = try #require(edges.keyboardTop)
        #expect(edges.after >= edges.before)
        #expect(edges.after > keyboardTop)
    }

    /// Content may scroll under the floating bar, but the page's safe area ends above it,
    /// so anything that respects it (the exercise strip, a Save button) rests clear of the bar.
    @Test func tabPageSafeAreaEndsAboveTheBottomBar() async throws {
        let bottom = try await bottomEdgeAroundNumberPad(screen: true, showNumberPad: false)
        let withoutBar = try await bottomEdgeAroundNumberPad(screen: true, showNumberPad: false, barVisible: false)
        #expect(bottom.before < withoutBar.before)
    }

    @Test func focusedRowScrollsAboveTheNumberPad() async throws {
        let edges = try await focusedRowAroundNumberPad(keepsFocus: true)
        #expect(edges.rowBottom <= edges.keyboardTop)
    }

    @Test func focusedRowWithoutKeepsFocusStaysCovered() async throws {
        let edges = try await focusedRowAroundNumberPad(keepsFocus: false)
        #expect(edges.rowBottom > edges.keyboardTop)
    }

    /// The bottom edge of a pushed screen's content before and after the number pad appears.
    private func bottomEdgeAroundNumberPad(
        screen optsOut: Bool,
        showNumberPad: Bool = true,
        barVisible: Bool = true,
        measureTabBar: Bool = false
    ) async throws -> (before: CGFloat, after: CGFloat, keyboardTop: CGFloat?) {
        let probe = BottomEdgeProbe()
        let screen = try await ScreenUnderTest(
            TabView {
                Tab("Programs", systemImage: "list.bullet.rectangle") {
                    NavigationStack {
                        Color.clear.navigationDestination(isPresented: .constant(true)) {
                            ProbeScreen(probe: probe, optsOut: optsOut)
                        }
                    }
                    .powerJackTabPage()
                    .toolbarVisibility(barVisible ? .visible : .hidden, for: .tabBar)
                }
                Tab("Templates", systemImage: "square.stack") { Color.clear }
            }
            .powerJackKeyboardBehavior()
        )
        defer { screen.close() }
        func edge() throws -> CGFloat { measureTabBar ? try screen.tabBarTop() : probe.bottom }
        let before = try edge()
        let keyboardTop = showNumberPad ? try await screen.showNumberPad() : nil
        #expect(before > 0)
        return (before, try edge(), keyboardTop)
    }

    /// Focuses the last row of a short list that starts out under the number pad,
    /// and returns where that row and the number pad end up.
    private func focusedRowAroundNumberPad(keepsFocus: Bool) async throws -> (rowBottom: CGFloat, keyboardTop: CGFloat) {
        let probe = FocusProbe()
        let screen = try await ScreenUnderTest(
            TabView {
                Tab("Programs", systemImage: "list.bullet.rectangle") {
                    NavigationStack {
                        Color.clear.navigationDestination(isPresented: .constant(true)) {
                            FocusProbeScreen(probe: probe, keepsFocus: keepsFocus)
                        }
                    }
                    .powerJackTabPage()
                }
                Tab("Templates", systemImage: "square.stack") { Color.clear }
            }
            .powerJackKeyboardBehavior()
        )
        defer { screen.close() }
        let keyboardTop = try await screen.showKeyboard { probe.focusRequested = true }
        if keepsFocus {
            // The scroll to the focused row runs slower on CI, so give it up to 3 seconds.
            for _ in 0..<30 where probe.rowBottom > keyboardTop {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        #expect(probe.rowBottom > 0)
        return (probe.rowBottom, keyboardTop)
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

    func tabBarTop() throws -> CGFloat {
        func findTabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            return view.subviews.lazy.compactMap(findTabBar).first
        }
        let bar = try #require(findTabBar(in: window))
        return bar.convert(bar.bounds, to: window).minY
    }

    /// Brings up the real number pad, the same keyboard the Weight and Reps fields use.
    func showNumberPad() async throws -> CGFloat {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        field.keyboardType = .decimalPad
        window.addSubview(field)
        self.field = field
        return try await showKeyboard { field.becomeFirstResponder() }
    }

    /// Runs `bringUp`, waits for the software keyboard to show and settle, and returns its top edge.
    @discardableResult
    func showKeyboard(_ bringUp: () -> Void) async throws -> CGFloat {
        var keyboardTop: CGFloat?
        let token = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
        ) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            MainActor.assumeIsolated { keyboardTop = frame?.minY }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        bringUp()
        for _ in 0..<30 where keyboardTop == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let top = try #require(keyboardTop, "The software keyboard didn't appear. Turn off Simulator > I/O > Keyboard > Connect Hardware Keyboard.")
        try await Task.sleep(for: .milliseconds(500))
        return top
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

@Observable
private final class FocusProbe {
    var focusRequested = false
    var rowBottom: CGFloat = 0
}

/// Stands in for a workout's sets: a short list of number fields whose last row
/// starts out where the number pad will cover it.
private struct FocusProbeScreen: View {
    private static let rows = 0..<10
    let probe: FocusProbe
    let keepsFocus: Bool

    @FocusState private var focusedRow: Int?

    var body: some View {
        let list = ScrollView {
            VStack(spacing: 0) {
                ForEach(Self.rows, id: \.self) { row in
                    TextField("Reps", text: .constant(""))
                        .keyboardType(.numberPad)
                        .focused($focusedRow, equals: row)
                        .frame(height: 60)
                        .id(row)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
                            if row == Self.rows.last { probe.rowBottom = bottom }
                        }
                }
            }
        }
        Group {
            if keepsFocus {
                list.keepsFocusAboveKeyboard(focusedRow)
            } else {
                list
            }
        }
        .keyboardSlidesOver()
        .onChange(of: probe.focusRequested) { focusedRow = Self.rows.last }
    }
}
