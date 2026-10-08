//
//  HostedView.swift
//  PowerJackTests
//
//  Puts a SwiftUI view on screen and drives it through its accessibility elements,
//  the same way VoiceOver activates a button, so tests can exercise view actions.
//

import SwiftUI
import UIKit

@MainActor
final class HostedView {
    let window: UIWindow
    private let host: UIViewController

    init<Content: View>(_ content: Content) async throws {
        Self.enableAccessibility()
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            throw HostedViewError.noScene
        }
        window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        await settle()
    }

    func close() {
        host.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Lets SwiftUI lay out, run `onAppear` and `task`, and finish short animations.
    func settle(_ duration: Duration = .milliseconds(300)) async {
        window.layoutIfNeeded()
        try? await Task.sleep(for: duration)
        window.layoutIfNeeded()
    }

    /// Settles until `condition` holds or `timeout` passes, for animations that run slower on CI.
    @discardableResult
    func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            await settle(.milliseconds(100))
        }
        return true
    }

    /// Every accessibility label currently in this view's window, including presented sheets.
    var labels: [String] {
        elements().compactMap { $0.accessibilityLabel }
    }

    func contains(_ label: String) -> Bool {
        labels.contains { $0 == label }
    }

    /// The first label that starts with `prefix`, for rows whose label joins a title and detail.
    func label(startingWith prefix: String) -> String? {
        labels.first { $0.hasPrefix(prefix) }
    }

    /// Steps the adjustable element at `index` (in screen order), like swiping up or down in VoiceOver.
    @discardableResult
    func adjust(at index: Int, increment: Bool) async -> Bool {
        let adjustables = elements().filter { $0.accessibilityTraits.contains(.adjustable) }
        guard adjustables.indices.contains(index) else { return false }
        if increment {
            adjustables[index].accessibilityIncrement()
        } else {
            adjustables[index].accessibilityDecrement()
        }
        await settle()
        return true
    }

    /// Activates the element with this label, like a VoiceOver double tap.
    /// Menus list an item twice (title and button), so each match is tried until one responds.
    @discardableResult
    func tap(_ label: String, settleFor duration: Duration = .milliseconds(300)) async -> Bool {
        let matches = elements().filter { $0.accessibilityLabel == label }
        guard !matches.isEmpty else { return false }
        let activated = matches.contains { $0.accessibilityActivate() }
        await settle(duration)
        return activated
    }

    /// Types into the text field with this accessibility label, replacing what it held.
    @discardableResult
    func type(_ text: String, into label: String) async -> Bool {
        guard
            let element = elements().first(where: { $0.accessibilityLabel == label }),
            let field = textField(at: CGPoint(x: element.accessibilityFrame.midX, y: element.accessibilityFrame.midY))
        else {
            return false
        }
        field.becomeFirstResponder()
        await settle()
        field.selectAll(nil)
        field.deleteBackward()
        field.insertText(text)
        await settle()
        return true
    }

    /// Types into the first text field on screen, replacing what it held.
    @discardableResult
    func typeIntoFirstField(_ text: String) async -> Bool {
        func search(_ view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            for subview in view.subviews {
                if let field = search(subview) { return field }
            }
            return nil
        }
        guard let field = search(window) else { return false }
        field.becomeFirstResponder()
        await settle()
        field.selectAll(nil)
        field.deleteBackward()
        field.insertText(text)
        await settle()
        return true
    }

    /// Scroll views whose content is wider than they are, so a sideways swipe scrolls them.
    var horizontalScrollViews: [UIScrollView] {
        func search(_ view: UIView) -> [UIScrollView] {
            var found = view.subviews.flatMap(search)
            if let scrollView = view as? UIScrollView,
               scrollView.contentSize.width > scrollView.bounds.width + 1 {
                found.append(scrollView)
            }
            return found
        }
        return search(window)
    }

    /// Ends editing, like tapping outside the keyboard.
    func dismissKeyboard() async {
        window.endEditing(true)
        await settle()
    }

    /// The text field under a point in screen coordinates.
    private func textField(at point: CGPoint) -> UITextField? {
        func search(_ view: UIView) -> UITextField? {
            if let field = view as? UITextField,
               field.convert(field.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(window.convert(point, from: nil)) {
                return field
            }
            for subview in view.subviews {
                if let field = search(subview) { return field }
            }
            return nil
        }
        return search(window)
    }

    // MARK: Accessibility tree

    /// SwiftUI only builds its accessibility elements while an assistive technology is
    /// running. Turning on automation mode, as UI tests do, builds them in-process.
    private static var accessibilityEnabled = false

    private static func enableAccessibility() {
        guard !accessibilityEnabled else { return }
        accessibilityEnabled = true
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW) else { return }
        typealias SetEnabled = @convention(c) (Bool) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            if let symbol = dlsym(handle, name) {
                unsafeBitCast(symbol, to: SetEnabled.self)(true)
            }
        }
    }

    private func elements() -> [NSObject] {
        var found: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        collect(window, into: &found, visited: &visited)
        return found
    }

    private func collect(_ object: NSObject, into found: inout [NSObject], visited: inout Set<ObjectIdentifier>) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        if object.isAccessibilityElement {
            found.append(object)
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject {
                    collect(child, into: &found, visited: &visited)
                }
            }
        }
        if let children = object.accessibilityElements as? [NSObject] {
            for child in children {
                collect(child, into: &found, visited: &visited)
            }
        }
        if let view = object as? UIView {
            for subview in view.subviews {
                collect(subview, into: &found, visited: &visited)
            }
        }
    }
}

enum HostedViewError: Error {
    case noScene
}
