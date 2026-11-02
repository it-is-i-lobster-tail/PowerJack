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

    @Test func focusedRowScrollsAboveTheNumberPad() async throws {
        let edges = try await focusedRowAroundNumberPad(keepsFocus: true)
        #expect(edges.rowBottom <= edges.keyboardTop)
    }

    @Test func focusedRowWithoutKeepsFocusStaysCovered() async throws {
        let edges = try await focusedRowAroundNumberPad(keepsFocus: false)
        #expect(edges.rowBottom > edges.keyboardTop)
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

    /// Focuses the last row of a short list that starts out under the number pad,
    /// and returns where that row and the number pad end up.
    private func focusedRowAroundNumberPad(keepsFocus: Bool) async throws -> (rowBottom: CGFloat, keyboardTop: CGFloat) {
        let probe = FocusProbe()
        let screen = try await ScreenUnderTest(
            TabView {
                Tab {
                    NavigationStack {
                        Color.clear.navigationDestination(isPresented: .constant(true)) {
                            FocusProbeScreen(probe: probe, keepsFocus: keepsFocus)
                        }
                    }
                    .powerJackTabPage(bottomBarHeight: Self.barHeight)
                }
            }
            .powerJackKeyboardBehavior()
        )
        defer { screen.close() }
        let keyboardTop = try await screen.showKeyboard { probe.focusRequested = true }
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

    /// Brings up the real number pad, the same keyboard the Weight and Reps fields use.
    func showNumberPad() async throws {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        field.keyboardType = .decimalPad
        window.addSubview(field)
        self.field = field
        try await showKeyboard { field.becomeFirstResponder() }
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
