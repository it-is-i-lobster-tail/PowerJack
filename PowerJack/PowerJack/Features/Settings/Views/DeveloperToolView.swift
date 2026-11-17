//
//  DeveloperToolView.swift
//  PowerJack
//
//  Turns the trace on and off, and lists, opens, deletes and shares its files (see `TraceLog`).
//

import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DeveloperToolView: View {
    private let traceLog: TraceLog

    @State private var isTracing: Bool
    @State private var files: [TraceLog.File] = []
    @State private var isConfirmingOn = false
    @State private var isConfirmingOff = false

    init(traceLog: TraceLog = .shared) {
        self.traceLog = traceLog
        _isTracing = State(initialValue: traceLog.isEnabled)
    }

    var body: some View {
        content.traceScreen("Developer Tool")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                Toggle("Trace Logging", isOn: tracing)
            } footer: {
                Text("Records every tap, screen, save and change to your training, rest timers and syncing, in files that stay on this iPhone until you share them. Names and anything you type are left out. Turning it off deletes the files.")
            }

            if isTracing || !files.isEmpty {
                Section("Files") {
                    if files.isEmpty {
                        Text("No files yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(files) { file in
                        NavigationLink {
                            TraceFileView(file: file, traceLog: traceLog)
                        } label: {
                            TraceFileRow(file: file)
                        }
                    }
                    .onDelete(perform: delete)
                }

                Section {
                    ShareLink(item: TraceArchive(traceLog: traceLog), preview: SharePreview("PowerJack Trace")) {
                        Label("Export All as Zip", systemImage: "square.and.arrow.up")
                    }
                    .disabled(files.isEmpty)
                }
            }
        }
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reloadFiles() }
        .refreshable { await reloadFiles() }
        .alert("Turn On Trace Logging?", isPresented: $isConfirmingOn) {
            Button("Accept and Turn On", action: turnOn)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Trace logging records every action you take in PowerJack, for debugging and developer improvement. It uses up to 50 MB on this iPhone and isn't recommended.")
        }
        .alert("Turn Off Trace Logging?", isPresented: $isConfirmingOff) {
            Button("Turn Off and Delete", role: .destructive, action: turnOff)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every trace file on this iPhone will be deleted.")
        }
    }

    // Both ways ask first: on records everything, off deletes the files.
    private var tracing: Binding<Bool> {
        Binding(
            get: { isTracing },
            set: { isOn in
                if isOn {
                    isConfirmingOn = true
                } else {
                    isConfirmingOff = true
                }
            }
        )
    }

    private func turnOn() {
        traceLog.setEnabled(true)
        isTracing = true
        Task { await reloadFiles() }
    }

    private func turnOff() {
        traceLog.setEnabled(false)
        isTracing = false
        files = []
    }

    private func delete(at offsets: IndexSet) {
        let deleted = offsets.map { files[$0] }
        files.remove(atOffsets: offsets)
        Task {
            for file in deleted { await traceLog.delete(file) }
            await reloadFiles()
        }
    }

    private func reloadFiles() async {
        await traceLog.flush()
        files = await traceLog.files()
    }
}

private struct TraceFileRow: View {
    let file: TraceLog.File

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.modified, format: .dateTime.month().day().hour().minute().second())
            Text(Int64(file.size), format: .byteCount(style: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every trace file in one zip, made only when it's shared.
private nonisolated struct TraceArchive: Transferable {
    let traceLog: TraceLog

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            SentTransferredFile(try await archive.traceLog.makeArchive())
        }
    }
}

/// One trace file, newest lines at the bottom.
private struct TraceFileView: View {
    let file: TraceLog.File
    let traceLog: TraceLog

    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                TraceText(text: text)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(file.modified, format: .dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await traceLog.flush()
            let url = file.url
            text = await Task.detached {
                (try? String(contentsOf: url, encoding: .utf8)) ?? "This file couldn't be read."
            }.value
        }
    }
}

/// A text view handles a 5 MB file smoothly and lets lines be selected and copied.
private struct TraceText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 32, right: 12)
        textView.text = text
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}
}

#Preview("Developer Tool") {
    NavigationStack {
        DeveloperToolView(traceLog: TraceLog(directory: .temporaryDirectory.appending(path: "PreviewTrace")))
    }
}
