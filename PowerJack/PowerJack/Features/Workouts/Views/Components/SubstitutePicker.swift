import SwiftData
import SwiftUI

struct SubstitutePicker: View {
    let workoutExercise: WorkoutExercise
    let onSelect: (Exercise) -> Void

    var body: some View {
        ExerciseSelectionView(navigationTitle: "Substitute", mode: .substitute(workoutExercise), onSelect: onSelect)
    }
}

#Preview("SubstitutePicker") {
    let scenario = PowerJackSeed.weekOneProgress()

    SubstitutePicker(workoutExercise: scenario.weekOneWorkouts[2].workoutExercises[0], onSelect: { _ in })
        .modelContainer(scenario.container)
}
