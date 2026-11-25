//
//  HostedView.swift
//  PowerJackTests
//
//  Puts a SwiftUI view on screen and drives it through its accessibility elements,
//  the same way VoiceOver activates a button, so tests can exercise view actions.
//

import os
import SwiftData
import SwiftUI
import UIKit
@testable import PowerJack

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

    /// A closed screen can still update once more after its test ends. Stores made here are kept
    /// for the whole run, so that late update never reads a model whose store was already reset.
    static func makeStore() -> ModelContainer {
        let container = PowerJackSeed.makeInMemoryContainer()
        keptStores.append(container)
        return container
    }

    /// Keeps a container the test didn't make here, such as one a store replaces, for the whole run.
    static func keep(_ container: ModelContainer) {
        keptStores.append(container)
    }

    private static var keptStores: [ModelContainer] = []

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

    /// Labels in every visible window of the scene, for menus, which open in a window of their own.
    var labelsInAllWindows: [String] {
        var found: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        for other in window.windowScene?.windows ?? [] where !other.isHidden {
            collect(other, into: &found, visited: &visited)
        }
        return found.compactMap { $0.accessibilityLabel }
    }

    func contains(_ label: String) -> Bool {
        labels.contains { $0 == label }
    }

    /// The first label that starts with `prefix`, for rows whose label joins a title and detail.
    func label(startingWith prefix: String) -> String? {
        labels.first { $0.hasPrefix(prefix) }
    }

    /// The value read out after the label, such as a picker's current choice.
    func value(of label: String) -> String? {
        elements().first { $0.accessibilityLabel == label }?.accessibilityValue
    }

    /// Where the element with this label sits on screen, for layout checks.
    func frame(of label: String) -> CGRect? {
        elements().first { $0.accessibilityLabel == label }?.accessibilityFrame
    }

    /// Where every element with this label sits on screen, for labels shown in more than one place.
    func frames(of label: String) -> [CGRect] {
        elements().filter { $0.accessibilityLabel == label }.map(\.accessibilityFrame)
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

    /// Drives the native segmented picker's value-change action in the hosted screen.
    func selectSegment(_ title: String) async -> Bool {
        func select(in view: UIView) -> Bool {
            guard !view.isHidden else { return false }
            if let control = view as? UISegmentedControl,
               control.isEnabled,
               let index = (0..<control.numberOfSegments).first(where: { control.titleForSegment(at: $0) == title }),
               control.isEnabledForSegment(at: index) {
                control.selectedSegmentIndex = index
                control.sendActions(for: .valueChanged)
                return true
            }
            return view.subviews.contains(where: select)
        }
        guard select(in: window) else { return false }
        await settle()
        return true
    }

    /// Activates the element with this label, like a VoiceOver double tap.
    /// Menus list an item twice (title and button), so each match is tried until one responds.
    @discardableResult
    func tap(_ label: String, settleFor duration: Duration = .milliseconds(300)) async -> Bool {
        let matches = elements().filter { $0.accessibilityLabel == label }
        // A duplicate accessibility element can claim activation while the alert stays open.
        let activated = runAlertAction(titled: label) || matches.contains { $0.accessibilityActivate() }
        guard activated || !matches.isEmpty else { return false }
        await settle(duration)
        return activated
    }

    /// In-process accessibility activation doesn't select native tab bar items.
    /// Drive the tab controller and deliver the same selection SwiftUI receives on a tap.
    @discardableResult
    func selectTab(_ title: String, settleFor duration: Duration = .milliseconds(600)) async -> Bool {
        func findTabs(in controller: UIViewController) -> UITabBarController? {
            if let tabs = controller as? UITabBarController { return tabs }
            return controller.children.lazy.compactMap(findTabs).first
        }
        if let controller = findTabs(in: host) {
            if let tab = controller.tabs.first(where: { $0.title == title }) {
                let previous = controller.selectedTab
                controller.selectedTab = tab
                controller.delegate?.tabBarController?(controller, didSelectTab: tab, previousTab: previous)
                await settle(duration)
                return controller.selectedTab == tab
            }
            // Earlier SwiftUI versions configure the controller through viewControllers and tabBarItem.
            if let child = controller.viewControllers?.first(where: { $0.tabBarItem.title == title }) {
                controller.selectedViewController = child
                controller.delegate?.tabBarController?(controller, didSelect: child)
                await settle(duration)
                return controller.selectedViewController === child
            }
        }
        // SwiftUI can also host the native tab bar directly.
        func findBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            return view.subviews.lazy.compactMap(findBar).first
        }
        if let bar = findBar(in: window), let item = bar.items?.first(where: { $0.title == title }),
           let select = bar.delegate?.tabBar(_:didSelect:) {
            select(bar, item)
            await settle(duration)
            return bar.selectedItem === item
        }
        return await tap(title, settleFor: duration)
    }

    /// On some iOS versions a SwiftUI confirmation dialog is a UIKit alert, whose buttons don't respond
    /// to `accessibilityActivate` in-process. Runs the alert button's own action instead, after
    /// dismissing the alert, the order UIKit uses when it's tapped.
    private func runAlertAction(titled title: String) -> Bool {
        var presented = host.presentedViewController
        while let controller = presented {
            if let alert = controller as? UIAlertController,
               let action = alert.actions.first(where: { $0.title == title && $0.isEnabled }),
               let block = action.value(forKey: "handler") {
                typealias Handler = @convention(block) (UIAlertAction) -> Void
                let handler = unsafeBitCast(block as AnyObject, to: Handler.self)
                alert.dismiss(animated: false) { handler(action) }
                return true
            }
            presented = controller.presentedViewController
        }
        return false
    }

    /// Types into the text field with this accessibility label, replacing what it held.
    @discardableResult
    func type(_ text: String, into label: String) async -> Bool {
        guard let field = textField(labeled: label) else { return false }
        field.becomeFirstResponder()
        await settle()
        field.selectAll(nil)
        field.deleteBackward()
        field.insertText(text)
        await settle()
        return true
    }

    /// Focuses the text field with this accessibility label and types, without clearing it first,
    /// so whatever the field selects on focus decides what the typing replaces.
    @discardableResult
    func focusAndType(_ text: String, into label: String) async -> Bool {
        guard let field = textField(labeled: label) else { return false }
        field.becomeFirstResponder()
        await settle()
        field.insertText(text)
        await settle()
        return true
    }

    /// Types into the first text field on screen, with an option to keep its existing text.
    @discardableResult
    func typeIntoFirstField(_ text: String, replacing: Bool = true) async -> Bool {
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
        if replacing {
            field.selectAll(nil)
            field.deleteBackward()
        }
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

    /// Scrolls every vertical list to its end, so rows below the fold get built.
    func scrollToBottom() async {
        func search(_ view: UIView) -> [UIScrollView] {
            var found = view.subviews.flatMap(search)
            if let scrollView = view as? UIScrollView,
               scrollView.contentSize.height > scrollView.bounds.height + 1 {
                found.append(scrollView)
            }
            return found
        }
        for scrollView in search(window) {
            let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: bottom), animated: false)
        }
        await settle()
    }

    /// Goes back one page in the front-most navigation stack, like the back button.
    @discardableResult
    func goBack(settleFor duration: Duration = .milliseconds(600)) async -> Bool {
        func stack(in controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController, navigation.viewControllers.count > 1 {
                return navigation
            }
            return controller.children.lazy.compactMap(stack).first
        }
        var front = window.rootViewController
        while let presented = front?.presentedViewController { front = presented }
        guard let front, let navigation = stack(in: front) else { return false }
        navigation.popViewController(animated: false)
        await settle(duration)
        return true
    }

    /// Ends editing, like tapping outside the keyboard.
    func dismissKeyboard() async {
        window.endEditing(true)
        await settle()
    }

    /// The text field under the element with this accessibility label.
    private func textField(labeled label: String) -> UITextField? {
        guard let element = elements().first(where: { $0.accessibilityLabel == label }) else { return nil }
        let frame = element.accessibilityFrame
        return textField(at: CGPoint(x: frame.midX, y: frame.midY))
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

/// Observe text as SwiftUI draws it. A separate Text.LayoutKey query can deadlock
/// with the display link while the hosted strip is scrolling.
nonisolated struct TextTruncationProbe: TextRenderer {
    private let observations = OSAllocatedUnfairLock(initialState: [Bool]())

    var truncated: [Bool] { observations.withLock { $0 } }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        observations.withLock { $0.append(layout.isTruncated) }
        for line in layout { context.draw(line) }
    }
}
