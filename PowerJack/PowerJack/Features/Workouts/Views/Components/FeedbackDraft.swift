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
    /// A PowerJack top set left unrated while its back sets were logged, so it's asked here.
    var asksTopSet = false
    var topSetRepsInReserve: RepsInReserve?

    var canSave: Bool {
        levelOfPain != nil
            && (ratesRepsInReserve ? repsInReserve != nil : levelOfEffort != nil)
            && (!asksTopSet || topSetRepsInReserve != nil)
    }

    init(ratesRepsInReserve: Bool = false, asksTopSet: Bool = false) {
        self.ratesRepsInReserve = ratesRepsInReserve
        self.asksTopSet = asksTopSet
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
