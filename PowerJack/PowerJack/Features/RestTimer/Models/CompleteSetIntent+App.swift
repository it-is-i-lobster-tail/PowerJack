//
//  CompleteSetIntent+App.swift
//  PowerJack
//
//  Runs the Live Activity's check button in the app, even when it is in the background.
//

import AppIntents
import Foundation
import SwiftData

extension CompleteSetIntent {
    @MainActor
    func perform() async throws -> some IntentResult {
        // The app's own context, so open screens see the set complete right away.
        let context = PowerJackApp.modelContainer.mainContext
        let program = try context.fetch(FetchDescriptor<Program>()).active
        let workout = program?.nextWorkout
        let completed = workout?.completeCurrentSet(exerciseOrder: exerciseOrder, setOrder: setOrder, workoutID: workoutID) == true
        if completed { try context.save() }

        // The app may not be on screen to notice, so move the activity on to the next set here.
        // A check that no longer matches, say because the watch logged that set, catches the activity up instead.
        await RestLiveActivityController.follow(program)
        // Starts the next rest's callout while the phone is still locked.
        if completed { RestVoice.shared.follow(workout) }
        return .result()
    }
}
