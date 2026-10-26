//
//  CopyDayMenu.swift
//  PowerJack
//

import SwiftUI

/// Copies the selected day's exercises to another day, then shows that day.
/// A day that already has exercises asks first whether to replace them or add to the end.
struct CopyDayMenu: View {
    let options: [BrowserOption]
    @Binding var selection: BrowserOption
    @Binding var draft: TemplateProgramDraft

    @State private var pendingDestination: BrowserOption?

    private var destinations: [BrowserOption] {
        options.filter { $0 != selection }
    }

    private func exerciseCount(of option: BrowserOption) -> Int {
        draft.templateWorkoutDraftsValue[option.index].templateExerciseDrafts.count
    }

    private func exerciseCountText(of option: BrowserOption) -> String {
        let count = exerciseCount(of: option)
        switch count {
        case 0: return "Empty"
        case 1: return "1 exercise"
        default: return "\(count) exercises"
        }
    }

    var body: some View {
        Menu {
            Section("Copy \(selection.name) to") {
                ForEach(destinations) { destination in
                    Button {
                        if exerciseCount(of: destination) == 0 {
                            copy(to: destination, replacing: true)
                        } else {
                            pendingDestination = destination
                        }
                    } label: {
                        Text(destination.name)
                        Text(exerciseCountText(of: destination))
                    }
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .accessibilityLabel("Copy Day")
        // An empty day has nothing to copy.
        .disabled(exerciseCount(of: selection) == 0)
        .confirmationDialog(
            "Replace \(pendingDestination?.name ?? "")?",
            isPresented: Binding(
                get: { pendingDestination != nil },
                set: { if !$0 { pendingDestination = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDestination
        ) { destination in
            Button("Replace", role: .destructive) {
                copy(to: destination, replacing: true)
            }
            Button("Add to End") {
                copy(to: destination, replacing: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { destination in
            let them = exerciseCount(of: destination) == 1 ? "it" : "them"
            Text("\(destination.name) has \(exerciseCountText(of: destination)). Copying \(selection.name) replaces \(them).")
        }
    }

    private func copy(to destination: BrowserOption, replacing: Bool) {
        draft.copyTemplateWorkout(
            from: selection.index,
            to: destination.index,
            replacing: replacing
        )
        withAnimation(.snappy) {
            selection = destination
        }
    }
}
