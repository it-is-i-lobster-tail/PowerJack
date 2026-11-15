//
//  TraceLog.swift
//  PowerJack
//
//  A developer trace of what happens in the app, kept in files on this iPhone and never uploaded.
//  Off by default. While off, `record` costs one flag read. Lines are written on a background
//  queue, so tracing never holds up the screen or a save, and a failed write is dropped quietly.
//  Callers keep names, typed text and anything else that could identify someone out of messages.
//

import Foundation
import OSLog
import Synchronization

nonisolated final class TraceLog: @unchecked Sendable {
    enum Category: String {
        case lifecycle, tap, screen, data, workout, timer, watch, iCloud, settings
    }

    /// A saved trace file.
    struct File: Identifiable, Hashable, Sendable {
        let url: URL
        let size: Int
        let modified: Date

        var id: URL { url }
    }

    static let shared = TraceLog(directory: .applicationSupportDirectory.appending(path: "TraceLogs"))

    /// Kept out of the `settings.` prefix so it stays on this device and never goes to the watch.
    static let enabledKey = "developer.traceLog"

    /// Where the last shared zip waits. Replaced by the next one, and deleted when tracing turns off.
    private static let exportDirectory = URL.temporaryDirectory.appending(path: "TraceExport")

    static let maxFileBytes = 5_000_000
    static let maxFiles = 10

    // Its own, since the shared loggers belong to the main actor.
    private static let logger = Logger(subsystem: "PowerJack", category: "Trace")

    let directory: URL
    private let maxFileBytes: Int
    private let maxFiles: Int
    private let enabled = Atomic(false)
    private let queue = DispatchQueue(label: "PowerJack.TraceLog", qos: .utility)
    private let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    // Only touched on `queue`.
    private var handle: FileHandle?
    private var currentURL: URL?
    private var currentSize = 0

    init(directory: URL, maxFileBytes: Int = TraceLog.maxFileBytes, maxFiles: Int = TraceLog.maxFiles) {
        self.directory = directory
        self.maxFileBytes = maxFileBytes
        self.maxFiles = maxFiles
    }

    var isEnabled: Bool { enabled.load(ordering: .relaxed) }

    /// Picks up the saved switch at launch.
    func start(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        enabled.store(true, ordering: .relaxed)
        write(.lifecycle, "Launched")
    }

    /// Turning tracing off deletes every trace file.
    func setEnabled(_ isOn: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.enabledKey)
        enabled.store(isOn, ordering: .relaxed)
        if isOn {
            write(.lifecycle, "Tracing turned on")
        } else {
            queue.async { self.deleteAllFiles() }
        }
    }

    /// Records one line on the shared trace, when it's on.
    static func record(_ category: Category, _ message: @autoclosure () -> String) {
        shared.write(category, message())
    }

    func write(_ category: Category, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let date = Date.now
        let text = message()
        queue.async {
            // Tracing may have been turned off, and the files deleted, since this line was queued.
            guard self.isEnabled else { return }
            self.append("\(date.formatted(self.timestamp)) [\(category.rawValue)] \(text)\n")
        }
    }

    /// Trace files, newest first.
    func files() async -> [File] {
        await onQueue { Array(self.listFiles().reversed()) }
    }

    func delete(_ file: File) async {
        await onQueue {
            if file.url == self.currentURL { self.closeFile() }
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    /// Waits until every queued line is written.
    func flush() async {
        await onQueue { try? self.handle?.synchronize() }
    }

    /// Zips every trace file into one file to share. No line is written while it's zipped.
    func makeArchive() async throws -> URL {
        try await onQueueThrowing {
            try? self.handle?.synchronize()
            let exportDirectory = Self.exportDirectory
            try? FileManager.default.removeItem(at: exportDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            let archive = exportDirectory.appending(path: "PowerJack-Trace-\(Self.fileStamp()).zip")

            // Reading a folder "for uploading" hands back a zip of it, with no zip code of our own.
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: self.directory, options: .forUploading, error: &coordinatorError) { zip in
                do {
                    try FileManager.default.copyItem(at: zip, to: archive)
                } catch {
                    copyError = error
                }
            }
            if let error = coordinatorError ?? copyError { throw error }
            return archive
        }
    }

    // MARK: Files (on `queue`)

    private func append(_ line: String) {
        if handle == nil { openFile() }
        guard let handle else { return }
        let data = Data(line.utf8)
        do {
            try handle.write(contentsOf: data)
            currentSize += data.count
        } catch {
            Self.logger.error("Could not write the trace: \(error.localizedDescription)")
            closeFile()
            return
        }
        if currentSize >= maxFileBytes { closeFile() }
    }

    /// Carries on in the newest file while it has room, so each launch doesn't use up a file of its own.
    private func openFile() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Traces stay on this device, out of iCloud and computer backups too.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = directory
            try folder.setResourceValues(values)

            let url: URL
            if let newest = listFiles().last, newest.size < maxFileBytes {
                url = newest.url
            } else {
                url = directory.appending(path: "trace-\(Self.fileStamp()).log")
                guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else { return }
            }
            let handle = try FileHandle(forWritingTo: url)
            currentSize = Int(try handle.seekToEnd())
            self.handle = handle
            currentURL = url
            pruneOldFiles()
            let gap = currentSize > 0 ? "\n" : ""
            append("\(gap)PowerJack \(Self.appVersion) on \(Self.deviceModel), \(ProcessInfo.processInfo.operatingSystemVersionString)\n")
        } catch {
            Self.logger.error("Could not open a trace file: \(error.localizedDescription)")
        }
    }

    private func closeFile() {
        try? handle?.close()
        handle = nil
        currentURL = nil
        currentSize = 0
    }

    private func pruneOldFiles() {
        let files = listFiles()
        for file in files.dropLast(maxFiles) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private func deleteAllFiles() {
        closeFile()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: Self.exportDirectory)
    }

    /// Oldest first. File names start with when they were made, so they sort by name.
    private func listFiles() -> [File] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let values = try? url.resourceValues(forKeys: keys)
                return File(url: url, size: values?.fileSize ?? 0, modified: values?.contentModificationDate ?? .distantPast)
            }
    }

    private func onQueue<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private func onQueueThrowing<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// UTC, so file names sort in the order they were made, e.g. 2026-11-15T03-33-01.123Z.
    private static func fileStamp() -> String {
        Date.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Device

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The hardware model, like iPhone17,1. Never the device's name, which is often its owner's.
    private static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) Simulator"
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
