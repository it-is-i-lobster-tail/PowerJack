import Foundation

/// Search descriptors describe the calculation, independently of the example lift in the gallery.
struct StudySearchMetadata {
    let question: String
    let measure: String
    let observation: String
    let coverage: String
    let keywords: Set<String>

    init(_ question: String, _ measure: String, _ observation: String, _ coverage: String, _ terms: String) {
        self.question = question
        self.measure = measure
        self.observation = observation
        self.coverage = coverage
        keywords = Set(terms.split(separator: " ").map(String.init))
    }
}

extension TrainingStudy {
    var searchMetadata: StudySearchMetadata {
        switch self {
        case .legWork:
            .init("How much work did each muscle get each week?",
                  "Set credits",
                  "muscle and week",
                  "primary and assisting credits",
                  "weekly exposure")
        case .armReps:
            .init("How many direct reps did I log over time?",
                  "Completed reps",
                  "muscle and calendar period",
                  "direct reps with known assisting reps shown separately",
                  "monthly totals")
        case .gluteSources:
            .init("Which exercises contributed the most work for this muscle?",
                  "Set credits",
                  "exercise",
                  "primary or assisting sets in identifiable exercise slots",
                  "contribution sources")
        case .frequency:
            .init("Which weekdays get the most working sets?",
                  "Completed working sets",
                  "weekday and week",
                  "logged workouts involving selected muscles",
                  "weekday frequency")
        case .repRanges:
            .init("Which rep range accounts for most of my sets?",
                  "Working sets by rep band",
                  "exercise and rep band",
                  "completed sets with positive reps",
                  "distribution bands")
        case .repChanges:
            .init("Which exercises gained or lost the most reps?",
                  "Change in direct reps",
                  "exercise across two periods",
                  "completed sets for primary muscles",
                  "increase decrease")
        case .legMax:
            .init("Are my estimated maxes trending up?",
                  "Best estimated one-rep max",
                  "lift and workout",
                  "loaded exercises with eligible sets and selected primary muscles",
                  "e1rm trends progression")
        case .records:
            .init("What is my heaviest set for exactly this many reps?",
                  "Best external load",
                  "exact rep count",
                  "completed loaded sets at the specified rep count",
                  "heaviest pr exact")
        case .fixedSquat:
            .init("Am I doing more reps at the same weight?",
                  "Opening set reps",
                  "session at fixed load",
                  "completed opening working set at the selected weight",
                  "fixed capacity")
        case .milestones:
            .init("When did I first reach this load for at least this many reps?",
                  "Running load record",
                  "workout",
                  "sets reaching the rep minimum with earlier history for the record",
                  "milestone milestones minimum")
        case .repeatBench:
            .init("How often did I complete every prescribed set?",
                  "Workouts meeting the prescription",
                  "matched workout",
                  "matching programmed sets, reps and load",
                  "repeatability prescription adherence")
        case .yearlyRecords:
            .init("How do my records this year compare with my lifetime bests?",
                  "Period and lifetime best load",
                  "lift at target reps",
                  "completed sets with exactly the selected rep count",
                  "lifetime annual")
        case .skipped:
            .init("How much of my planned work did I skip?",
                  "Planned, completed and skipped sets",
                  "exercise",
                  "working sets with known status",
                  "skipped missed compliance")
        case .effort:
            .init("Was my effort on target?",
                  "Reported and target reps in reserve",
                  "exercise session",
                  "known ratings and prescription, with unrated sessions identified",
                  "effort rir reserve")
        case .lastCurl:
            .init("How did I do across two comparable sessions?",
                  "Change in reps by set",
                  "set position across two sessions",
                  "matched working load",
                  "matched comparison")
        case .benchSets:
            .init("Where do my reps drop off across sets?",
                  "Reps and first-to-final change",
                  "set position within session",
                  "matching load and programmed set count",
                  "fatigue dropoff")
        case .substitutions:
            .init("What did I do in place of my planned exercise?",
                  "Performed exercise share",
                  "planned exercise slot",
                  "completed slots with known planned exercise",
                  "substitute substitution replacements")
        case .exerciseOrder:
            .init("Do I get more reps when I do this lift first?",
                  "Median opening reps",
                  "exercise order group",
                  "comparable opening sets",
                  "order position")
        case .returnToSquat:
            .init("How long did it take to regain performance after a break?",
                  "Opening reps versus prior baseline",
                  "visit after a training gap",
                  "comparable openings before and after a gap",
                  "layoff comeback recovery")
        case .blocks:
            .init("Which training block produced the largest strength gain?",
                  "Percent change from week one",
                  "week within block",
                  "eligible estimates with a recorded block week",
                  "blocks cycles")
        case .duration:
            .init("How often do I finish my workout within my time budget?",
                  "Completed workouts within duration",
                  "workout in matching routine",
                  "known duration excluding pauses",
                  "minutes duration budget")
        case .goal:
            .init("How close am I to my rep goal?",
                  "Cumulative completed reps",
                  "dated progress toward rep goal",
                  "completed reps in selected period",
                  "goal progress cumulative")
        case .recency:
            .init("Which muscles have gone longest without direct work?",
                  "Days since last direct work",
                  "muscle as of selected date",
                  "primary muscle of completed working sets",
                  "recency neglected")
        case .repMix:
            .init("Did load change at the same reps or did my rep mix change?",
                  "Mean external load",
                  "rep count across two periods",
                  "matching reps in both periods",
                  "mix distribution")
        case .relationship:
            .init("Do changes in two lifts tend to move together?",
                  "Paired changes in strength estimates",
                  "matched weeks across two lifts",
                  "eligible estimates for both exercises",
                  "correlation relationship")
        case .typicalBench:
            .init("Was my latest estimate outside my usual range?",
                  "Latest estimate and prior quartiles",
                  "latest session versus baseline sessions",
                  "eligible strength estimates",
                  "typical variability quartiles")
        case .forecast:
            .init("Which method predicted my next estimate more accurately?",
                  "Forecast and absolute error",
                  "forecast date and method",
                  "eligible observed and predicted estimates",
                  "forecast prediction accuracy")
        case .squatSuccess:
            .init("How often do I hit my prescribed reps at each load?",
                  "Successful and attempted opening sets",
                  "opening load",
                  "logged openings with the target prescription",
                  "success attempts")
        case .missingEstimates:
            .init("Why are there gaps in my strength trend?",
                  "Eligible and logged sessions",
                  "calendar week",
                  "recorded lift sessions checked for estimate eligibility",
                  "gaps missing eligibility")
        case .pushups:
            .init("Are my best set and total reps increasing together?",
                  "Best set and total completed reps",
                  "reps-only exercise session",
                  "sessions matching the completed set count",
                  "bodyweight total")
        case .tonnage:
            .init("Why did my volume load change between workouts?",
                  "Total external load times reps and change",
                  "two workouts",
                  "completed loaded working sets",
                  "tonnage workload change")
        case .sessionLedger:
            .init("What exactly did I do in my first matching workout?",
                  "Recorded sets, reps and loads",
                  "working set within workout",
                  "the earliest matching workout in scope",
                  "ledger log details")
        }
    }
}
