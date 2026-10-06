//
//  ProgramDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/18/26.
//

struct ProgramDraft {
    var programLengthWeeks: Int?
    var templateProgram: TemplateProgram?

    init(
        programLengthWeeks: Int? = nil,
        templateProgram: TemplateProgram? = nil
    ) {
        self.programLengthWeeks = programLengthWeeks
        self.templateProgram = templateProgram
    }

    var canSave: Bool {
        programLengthWeeks != nil &&
        templateProgram?.draft == false
    }

    func makeProgram() -> Program? {
        guard let programLengthWeeks,
              let templateProgram,
              !templateProgram.draft
        else {
            return nil
        }

        return Program(
            programLengthWeeks: programLengthWeeks,
            templateProgram: templateProgram
        )
    }
}
