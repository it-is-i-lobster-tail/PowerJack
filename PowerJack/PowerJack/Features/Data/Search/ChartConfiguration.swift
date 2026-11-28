import Foundation

struct GalleryCardID: Hashable {
    let study: TrainingStudy
    let exerciseKeys: [String]
    /// A direct answer can use the same chart as a ranked card below it.
    var isAnswer = false
    /// A starred chart opens with its own saved choices.
    var favorite: UUID?
}

/// One tile in the gallery: a chart, configured for the search, with its computed result.
struct GalleryCard: Identifiable {
    let id: GalleryCardID
    let options: StudyOptions
    let result: StudyResult
}

/// Keep a search phrase only while its original selection still describes the chart.
struct StudySearchFocus: Equatable, Codable {
    let name: String
    let muscles: [Muscle]
    let exercises: [String]

    func describes(_ options: StudyOptions) -> Bool {
        Set(muscles) == Set(options.muscles) && Set(exercises) == Set(options.exerciseKeys)
    }
}

extension ChartQuery {
    /// The search's scope applied to one chart, starting from the chart's saved controls.
    /// Empty when the chart can't show that scope, such as a lift filter on a muscle-credit chart.
    /// A chart about one lift gets one configuration for each matching lift.
    func options(for study: TrainingStudy, saved: StudyOptions, history: StudyHistory) -> [StudyOptions] {
        var options = saved
        options.showsFullSearchTitle = true
        if let period { options.period = study == .repChanges ? comparedPeriod(in: history.calendar) ?? period : period }
        let supported = study.parameters.map(\.0)
        for (key, value) in parameters {
            let target: StudyParameter =
                key == .reps && supported.contains(.goalReps) ? .goalReps
                : key == .comparisonDays && supported.contains(.gapDays) ? .gapDays : key
            guard supported.contains(target), target.range.contains(value) else { return [] }
            options.parameters[target] = value
        }
        guard hasScope else { return [options] }
        options.searchFocus = nil
        options.muscles = []
        options.exerciseKeys = []
        options.secondExercise = nil

        if lifts.isEmpty, study.hasMuscleFocus {
            options.muscles = muscles
            options.searchFocus = StudySearchFocus(name: muscleGroups.map(\.name).formatted(.list(type: .and)),
                                                   muscles: muscles, exercises: [])
            return [options]
        }
        func canShow(_ key: String) -> Bool {
            guard let session = history.sessions.first(where: { $0.key == key }) else { return true }
            if study == .pushups { return session.repsOnly }
            return study.needsExternalLoad ? session.loaded : true
        }
        // A muscle search on a one-lift chart uses that muscle's most-logged lift.
        let keys = lifts.isEmpty ? Array(mostLoggedLift(for: muscles, in: history).prefix(1)) : exerciseKeys
        let eligible = keys.filter(canShow)
        // Muscle credits come from the log, which can't say which exercise earned them.
        guard !eligible.isEmpty, study != .legWork else { return [] }

        if study == .relationship {
            // One lift from each named subject when there are two, otherwise the two most-logged matches.
            let pair = lifts.count >= 2
                ? lifts.compactMap { $0.exerciseKeys.first(where: eligible.contains) }.uniqued()
                : eligible
            guard pair.count >= 2 else { return [] }
            options.exerciseKeys = [pair[0]]
            options.secondExercise = pair[1]
            return [options]
        }
        if study.multipleExercises {
            options.exerciseKeys = eligible
            options.muscles = lifts.isEmpty ? muscles : []
            let name = (lifts.isEmpty ? muscleGroups.map(\.name) : lifts.map(\.name)).formatted(.list(type: .and))
            options.searchFocus = StudySearchFocus(name: name, muscles: options.muscles, exercises: eligible)
            return [options]
        }
        // One card for each lift named, on its most trained lift: "squat" is one card, "bench and squat" two.
        let named = lifts.isEmpty ? Array(eligible.prefix(1)) : lifts.compactMap { $0.exerciseKeys.first(where: canShow) }.uniqued()
        return named.map { key in
            var variant = options
            variant.exerciseKeys = [key]
            return variant
        }
    }

    /// Two periods that follow each other, as in "October vs November", compare on the rep-change
    /// chart, which sets the later one against the equally long time before it.
    private func comparedPeriod(in calendar: Calendar) -> StudyPeriod? {
        guard periods.count == 2,
              let first = periods[0].interval(in: calendar), let second = periods[1].interval(in: calendar) else { return nil }
        if first.end == second.start { return periods[1] }
        if second.end == first.start { return periods[0] }
        return nil
    }

    private func mostLoggedLift(for muscles: [Muscle], in history: StudyHistory) -> [String] {
        let sessions = history.sessions.filter { $0.primary.map(muscles.contains) == true && !$0.done.isEmpty }
        let counts = Dictionary(grouping: sessions, by: \.key).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }
}

extension TrainingStudy {
    /// Charts built from estimated maxes or external load can't show a bodyweight-only lift.
    var needsExternalLoad: Bool {
        switch self {
        case .legMax, .records, .fixedSquat, .milestones, .repeatBench, .yearlyRecords, .exerciseOrder, .returnToSquat, .blocks,
            .relationship, .typicalBench, .forecast, .missingEstimates, .tonnage, .repMix, .squatSuccess:
            true
        default: false
        }
    }
}
