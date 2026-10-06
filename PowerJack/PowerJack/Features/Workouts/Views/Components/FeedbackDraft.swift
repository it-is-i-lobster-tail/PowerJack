//
//  FeedbackDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/15/26.
//

struct FeedbackDraft {
    var levelOfEffort: LevelOfEffort?
    var levelOfPain: LevelOfPain?

    var canSave: Bool {
        levelOfPain != nil && levelOfEffort != nil
    }

    init() {}

    init(exerciseFeedback: ExerciseFeedback) {
        levelOfEffort = exerciseFeedback.levelOfEffort
        levelOfPain = exerciseFeedback.levelOfPain
    }
}
