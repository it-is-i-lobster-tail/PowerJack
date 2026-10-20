//
//  FeedbackDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/15/26.
//

struct FeedbackDraft {
    /// Effort is rated as reps left on the last set instead of with an effort word.
    var ratesRepsInReserve = false
    var levelOfEffort: LevelOfEffort?
    var repsInReserve: RepsInReserve?
    var levelOfPain: LevelOfPain?

    var canSave: Bool {
        levelOfPain != nil && (ratesRepsInReserve ? repsInReserve != nil : levelOfEffort != nil)
    }

    init(ratesRepsInReserve: Bool = false) {
        self.ratesRepsInReserve = ratesRepsInReserve
    }

    init(exerciseFeedback: ExerciseFeedback) {
        repsInReserve = exerciseFeedback.repsInReserve
        ratesRepsInReserve = repsInReserve != nil
        levelOfEffort = exerciseFeedback.levelOfEffort
        levelOfPain = exerciseFeedback.levelOfPain
    }

    /// The feedback to save, once every question is answered.
    func makeFeedback() -> ExerciseFeedback? {
        guard canSave, let levelOfPain else { return nil }
        if ratesRepsInReserve, let repsInReserve {
            return ExerciseFeedback(repsInReserve: repsInReserve, levelOfPain: levelOfPain)
        }
        return levelOfEffort.map { ExerciseFeedback(levelOfEffort: $0, levelOfPain: levelOfPain) }
    }
}
