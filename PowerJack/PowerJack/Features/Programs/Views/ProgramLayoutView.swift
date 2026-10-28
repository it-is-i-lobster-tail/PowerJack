//
//  ProgramLayoutView.swift
//  PowerJack
//

import SwiftData
import SwiftUI

/// Edits the exercises on a running program's days in the template builder, saving every change as it happens.
/// Days already started this week stay as they are.
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
            lockedDays: draft.lockedDays
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
