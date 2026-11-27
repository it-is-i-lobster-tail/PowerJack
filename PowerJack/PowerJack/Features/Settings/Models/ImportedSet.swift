import Foundation
import SwiftData

/// A dated observation, independent of PowerJack's program and workout lifecycle.
@Model
final class ImportedSet {
    // Speeds up fetches that filter or sort by these. Local store only: iCloud records carry no indexes.
    // Indexes alone don't change the model's hash, so the hash modifier below makes existing stores migrate and build them.
    #Index<ImportedSet>([\.trainingDay], [\.exerciseKey])

    var sourceKey = ""
    var sourceExercise = ""
    var sourceCategory = ""
    @Attribute(hashModifier: "indexes-1")
    var trainingDay = ""
    var exerciseKey = ""
    var exerciseName = ""
    var muscle = ""
    var reps: Int?
    var weightTenthsPounds: Int?
    var durationSeconds: Int?
    var distance: Double?
    var distanceUnit = ""
    var comment = ""
    var sourceOrder = 0

    init() {}
}
