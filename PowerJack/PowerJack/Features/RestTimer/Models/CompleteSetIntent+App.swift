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
        guard
            let program = try context.fetch(FetchDescriptor<Program>()).active,
            let workout = program.nextWorkout,
            workout.completeCurrentSetAtTarget(exerciseOrder: exerciseOrder, setOrder: setOrder)
        else {
            return .result()
        }
        try context.save()

        // The app may not be on screen to notice, so move the activity on to the next set here.
        await RestLiveActivityController.sync(
            state: workout.activityState(),
            workoutTitle: program.activityTitle(for: workout),
            isEnabled: UserDefaults.standard.object(forKey: AppSettings.Key.restLiveActivity) as? Bool
                ?? AppSettings.Default.restLiveActivity
        )
        return .result()
    }
}
