import Foundation

/// A fixed query has one stable navigation identity and produces the same figure for both presentations.
enum TrainingStudy: Int, CaseIterable, Identifiable {
    case legWork = 1
    case armReps, gluteSources, frequency, repRanges, repChanges, legMax, records
    case fixedSquat, milestones, repeatBench, yearlyRecords, skipped, effort, lastCurl, benchSets
    case substitutions, exerciseOrder, returnToSquat, blocks, duration, goal, recency, repMix
    case relationship, typicalBench, forecast
    case squatSuccess = 29
    case missingEstimates
    case pushups = 33
    case tonnage, sessionLedger

    var id: Self { self }

    var caption: String {
        switch self {
        case .legWork: "Weekly leg muscle work"
        case .armReps: "Monthly arm rep totals"
        case .gluteSources: "Exercises behind glute volume"
        case .frequency: "Leg work by weekday"
        case .repRanges: "Leg exercise rep ranges"
        case .repChanges: "Changes in arm reps"
        case .legMax: "Estimated leg strength trends"
        case .records: "Squat records by reps"
        case .fixedSquat: "Squat reps at fixed load"
        case .milestones: "Five rep squat milestones"
        case .repeatBench: "Repeatable five rep bench sets"
        case .yearlyRecords: "Year and lifetime records"
        case .skipped: "Planned and skipped sets"
        case .effort: "Target and reported effort"
        case .lastCurl: "Compare recent curl sessions"
        case .benchSets: "Bench reps across sets"
        case .substitutions: "Back squat exercise substitutions"
        case .exerciseOrder: "Curl strength by exercise order"
        case .returnToSquat: "Squat performance after breaks"
        case .blocks: "Squat gains across blocks"
        case .duration: "Lower workout completion times"
        case .goal: "Progress toward squat rep goal"
        case .recency: "Days since direct leg work"
        case .repMix: "Bench load by rep range"
        case .relationship: "Squat and lunge relationship"
        case .typicalBench: "Bench versus recent range"
        case .forecast: "Bench estimate forecast errors"
        case .squatSuccess: "Five rep squat success"
        case .missingEstimates: "Gaps in squat estimates"
        case .pushups: "Push-up reps over time"
        case .tonnage: "Changes in squat volume load"
        case .sessionLedger: "First leg workout sets"
        }
    }
}

struct StudyPoint: Equatable {
    let x: Double
    let y: Double
    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

struct StudySeries: Equatable {
    enum Style { case line, step, dots, fit, bars }
    let name: String
    let points: [StudyPoint]
    var style: Style = .line
}

struct StudyBar: Equatable {
    let label: String
    let value: Double
    var group = ""
}

struct StudyTable: Equatable {
    var columns: [String]
    var rows: [[String]]
}

struct StudyCategoryPoint: Equatable {
    let category: String
    let series: String
    let value: Double
}

struct StudyCount: Equatable {
    let label: String
    let made: Int
    let attempts: Int
}

enum StudyFigure: Equatable {
    case traces([StudySeries], dates: Bool)
    case liftPanels([StudySeries])
    case comparison([StudyCategoryPoint], connected: Bool)
    case attempts([StudyCount])
    case bars([StudyBar])
    case matrix(columns: [String], rows: [String], values: [[Double?]])
    case table(StudyTable)
}

struct StudyResult: Identifiable, Equatable {
    let id: TrainingStudy
    var scope: String
    var figure: StudyFigure?
    var xLabel = ""
    var yLabel = ""
    var summary = ""
    var detail: StudyTable?
    var emptyReason = "Log matching working sets to see this chart."
    var alternateBars: [StudyBar] = []
    var title: StudyTitle?
    var presentation: StudyPresentation = .original
    var horizontalCategories = false

    var displayTitle: String { title?.full ?? id.caption }
    var galleryCaption: String { title?.caption ?? id.genericName }
    var galleryAccessibilityLabel: String { title?.full ?? id.genericName }
}

extension Double {
    var studyNumber: String { formatted(.number.precision(.fractionLength(0...1))) }
}
