//
//  PreviewProgram.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

class PreviewProgram {
    static let programPreview = Program(
        programLengthWeeks: 8,
        status: Status.active,
        templateProgram: PreviewTemplateProgram.templateProgramPreview,
        programWeeks: [
            PreviewProgramWeek.programWeekPreview0,
            PreviewProgramWeek.programWeekPreview1,
            PreviewProgramWeek.programWeekPreview2,
            PreviewProgramWeek.programWeekPreview3,
            PreviewProgramWeek.programWeekPreview4,
            PreviewProgramWeek.programWeekPreview5,
            PreviewProgramWeek.programWeekPreview6,
            PreviewProgramWeek.programWeekPreview7,
        ]
    )
}
