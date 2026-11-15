//
//  TraceLogTests.swift
//  PowerJackTests
//
//  The developer trace: off by default, rotates its files, deletes them when turned off,
//  zips them to share, and keeps names the lifter typed out of its lines.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct TraceLogTests {
    // A space, like Application Support's, catches paths passed on still percent-encoded.
    private let directory = URL.temporaryDirectory.appending(path: "Trace Log Tests \(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "TraceLogTests-\(UUID().uuidString)")!

    private func makeLog(maxFileBytes: Int = TraceLog.maxFileBytes, maxFiles: Int = TraceLog.maxFiles) -> TraceLog {
        TraceLog(directory: directory, maxFileBytes: maxFileBytes, maxFiles: maxFiles)
    }

    private func contents(of log: TraceLog) async throws -> String {
        await log.flush()
        return try await log.files().reversed().map { try String(contentsOf: $0.url, encoding: .utf8) }.joined()
    }

    @Test("Off by default, and nothing is written while off")
    func offByDefault() async {
        let log = makeLog()
        log.start(defaults: defaults)
        log.write(.tap, "Tap at (1, 2)")
        await log.flush()

        #expect(!log.isEnabled)
        #expect(await log.files().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test("The switch stays on this device: it never syncs to the watch")
    func switchIsDeviceOnly() {
        #expect(!TraceLog.enabledKey.hasPrefix(SettingsSync.keyPrefix))
    }

    @Test("Turned on, it writes timestamped lines under a header, and stays on after a relaunch")
    func writesLines() async throws {
        let log = makeLog()
        log.setEnabled(true, defaults: defaults)
        log.write(.tap, "Tap at (10, 20)")

        let text = try await contents(of: log)
        #expect(text.hasPrefix("PowerJack "))
        #expect(text.contains("[lifecycle] Tracing turned on"))
        #expect(text.contains("[tap] Tap at (10, 20)"))

        // A relaunch carries on in the same file while it has room.
        let relaunched = makeLog()
        relaunched.start(defaults: defaults)
        #expect(relaunched.isEnabled)
        relaunched.write(.tap, "After relaunch")
        await relaunched.flush()
        let files = await relaunched.files()
        #expect(files.count == 1)
        #expect(try String(contentsOf: try #require(files.first).url, encoding: .utf8).contains("After relaunch"))
    }

    @Test("A full file starts the next, and only the newest files are kept")
    func rotates() async throws {
        let log = makeLog(maxFileBytes: 400, maxFiles: 3)
        log.setEnabled(true, defaults: defaults)
        for number in 1...100 {
            log.write(.workout, "Line \(number)")
        }
        await log.flush()

        let files = await log.files()
        #expect(files.count == 3)
        #expect(files.allSatisfy { $0.size < 400 + 100 })
        // Newest first, holding the last line written.
        let newest = try String(contentsOf: try #require(files.first).url, encoding: .utf8)
        #expect(newest.contains("Line 100"))
        let all = try await contents(of: log)
        #expect(!all.contains("Line 1\n"))
    }

    @Test("Turning it off deletes every file")
    func turningOffDeletes() async {
        let log = makeLog()
        log.setEnabled(true, defaults: defaults)
        log.write(.workout, "Something")
        await log.flush()
        #expect(await log.files().count == 1)

        log.setEnabled(false, defaults: defaults)
        log.write(.workout, "After")
        await log.flush()

        #expect(await log.files().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        #expect(!defaults.bool(forKey: TraceLog.enabledKey))
    }

    @Test("Deleting the file being written starts a new one")
    func deletingCurrentFile() async throws {
        let log = makeLog()
        log.setEnabled(true, defaults: defaults)
        log.write(.workout, "First")
        await log.flush()
        await log.delete(try #require(await log.files().first))
        #expect(await log.files().isEmpty)

        log.write(.workout, "Second")
        let text = try await contents(of: log)
        #expect(text.contains("Second"))
        #expect(!text.contains("First"))
    }

    @Test("Every file goes into one zip to share")
    func archive() async throws {
        let log = makeLog(maxFileBytes: 200)
        log.setEnabled(true, defaults: defaults)
        for number in 1...20 {
            log.write(.workout, "Line \(number)")
        }

        let archive = try await log.makeArchive()
        let data = try Data(contentsOf: archive)
        #expect(archive.pathExtension == "zip")
        #expect(data.prefix(2) == Data("PK".utf8))
        #expect(await log.files().count > 1)

        log.setEnabled(false, defaults: defaults)
        await log.flush()
        #expect(!FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)))
    }

    @Test("Names the lifter typed stay out of trace lines")
    func keepsNamesOut() {
        let custom = Exercise(exerciseName: "Private Name Press", exerciseEquipment: .barbell, primaryMuscleFocus: .chest, userCreated: true)
        let builtIn = Exercise(exerciseName: "Bench Press", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)

        #expect(!custom.traceName.contains("Private"))
        #expect(custom.traceName.hasPrefix("custom exercise"))
        #expect(builtIn.traceName == builtIn.exerciseName)
        #expect(TraceLog.load(tenthsPounds: 1355, reps: 8) == "135.5 lb × 8")
        #expect(TraceLog.load(tenthsPounds: 1350, reps: 8) == "135 lb × 8")
        #expect(TraceLog.load(tenthsPounds: 0, reps: nil) == "BW × –")
    }
}
