import Testing
@testable import PowerJack

/// The status line and spoken reason on a FitNotes import row.
struct FitNotesRowStatusTests {
    @Test func statusPerRowState() {
        #expect(FitNotesImportView.status(confirmed: true, skipped: false, suggested: true, choiceCount: 0)
                == "PowerJack · Confirmed")
        #expect(FitNotesImportView.status(confirmed: false, skipped: true, suggested: false, choiceCount: 0)
                == "PowerJack · Skipped")
        #expect(FitNotesImportView.status(confirmed: false, skipped: false, suggested: true, choiceCount: 0)
                == "PowerJack · Suggested")
        #expect(FitNotesImportView.status(confirmed: false, skipped: false, suggested: false, choiceCount: 3)
                == "PowerJack · 3 choices")
        #expect(FitNotesImportView.status(confirmed: false, skipped: false, suggested: false, choiceCount: 1)
                == "PowerJack")
    }

    @Test func skippedWinsOverASuggestion() {
        #expect(FitNotesImportView.status(confirmed: false, skipped: true, suggested: true, choiceCount: 0)
                == "PowerJack · Skipped")
    }

    @Test func everySkipReasonIsSpokenAsSkipped() {
        for reason in ImportSkipReason.allCases {
            #expect(reason.spokenLabel.hasPrefix("Skipped"))
        }
        #expect(ImportSkipReason.stretchOrPT.spokenLabel == "Skipped, stretch or PT")
    }
}
