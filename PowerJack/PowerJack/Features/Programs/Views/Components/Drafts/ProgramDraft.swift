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
        templateProgram != nil
    }

    func makeProgram() -> Program? {
        guard let programLengthWeeks,
              let templateProgram
        else {
            return nil
        }

        return Program(
            programLengthWeeks: programLengthWeeks,
            templateProgram: templateProgram
        )
    }
}
