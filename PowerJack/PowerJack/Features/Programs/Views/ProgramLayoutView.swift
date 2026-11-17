//
//  ProgramLayoutView.swift
//  PowerJack
//

import SwiftData
import SwiftUI

/// Edits the exercises on a running program's days in the template builder, saving every change as it happens.
/// Days not started yet and the day in progress change now, keeping anything logged. Days already done
/// this week stay as they are, and change from next week.
struct ProgramLayoutView: View {
    @Environment(\.modelContext) private var modelContext

    let program: Program

    @State private var draft: ProgramLayoutDraft
    @State private var saveErrorMessage: String?

    init(program: Program) {
        self.program = program
        _draft = State(initialValue: ProgramLayoutDraft(program: program))
    }

    var body: some View {
        TemplateBuilder(
            draft: $draft.days.onSet(save),
            lockedDays: draft.lockedDays,
            dayNotes: draft.dayNotes,
            loggedExercises: draft.loggedExercises,
            keepsOneExercisePerDay: true
        )
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        draft.apply()

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            draft = ProgramLayoutDraft(program: program)
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("ProgramLayoutView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramLayoutView(program: scenario.program)
    }
}
