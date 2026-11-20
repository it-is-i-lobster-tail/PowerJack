//
//  AppearanceTests.swift
//  PowerJackTests
//
//  The Appearance setting: System follows the iPhone, Light and Dark force a style,
//  and a change reaches every screen, including the Settings tab.
//

import SwiftUI
import Testing
import UIKit
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct AppearanceTests {
    private let defaults = UserDefaults.standard
    private let key = AppSettings.Key.appearance

    @Test("System is the default and leaves the style to the iPhone")
    func defaultChoice() {
        #expect(AppSettings.Default.appearance == .system)
        #expect(Appearance.allCases.map(\.name) == ["System", "Light", "Dark"])
        #expect(Appearance.system.userInterfaceStyle == .unspecified)
        #expect(Appearance.light.userInterfaceStyle == .light)
        #expect(Appearance.dark.userInterfaceStyle == .dark)
    }

    @Test("A saved choice is used at launch")
    func savedChoiceAtLaunch() async throws {
        let saved = defaults.object(forKey: key)
        defer { defaults.set(saved, forKey: key) }
        defaults.set(Appearance.light.rawValue, forKey: key)

        let screen = try await HostedView(PowerJackAppContent().environment(PowerJackStore(inMemory: true)))
        defer { screen.close() }

        #expect(screen.window.overrideUserInterfaceStyle == .light)
        #expect(screen.window.traitCollection.userInterfaceStyle == .light)
    }

    @Test("Switching reaches the Settings tab, and System hands the style back to the iPhone")
    func switchesOpenSettingsTab() async throws {
        let saved = defaults.object(forKey: key)
        defer { defaults.set(saved, forKey: key) }
        defaults.removeObject(forKey: key)

        let screen = try await HostedView(PowerJackAppContent().environment(PowerJackStore(inMemory: true)))
        defer { screen.close() }
        let iPhoneStyle = try #require(screen.window.windowScene).traitCollection.userInterfaceStyle
        let forced: Appearance = iPhoneStyle == .dark ? .light : .dark

        #expect(screen.window.overrideUserInterfaceStyle == .unspecified)
        #expect(await screen.selectTab("Settings", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(screen.contains("Appearance"))
        let root = try #require(screen.window.rootViewController)
        #expect(root.presentedViewController == nil)

        defaults.set(forced.rawValue, forKey: key)
        await screen.settle()
        #expect(root.traitCollection.userInterfaceStyle == forced.userInterfaceStyle)

        defaults.set(Appearance.system.rawValue, forKey: key)
        await screen.settle()
        #expect(screen.window.overrideUserInterfaceStyle == .unspecified)
        #expect(root.traitCollection.userInterfaceStyle == iPhoneStyle)
    }
}
