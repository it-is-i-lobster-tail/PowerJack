import CryptoKit
import Foundation
import FoundationModels
import NaturalLanguage

enum WorkoutReminderCopy {
    static let fallback = "Check out the Preview"

    struct Facts {
        let program: String
        let trainingStyle: String
        let phase: String
        let timing: String
        let week: Int?
        let day: Int
        let focus: [String]
        let exercises: [Lift]
        let achievement: WorkoutAchievement?
        let unit: WeightUnit
        let weeks: Int
        let daysPerWeek: Int

        struct Lift {
            let exercise: String
            let muscle: String
            let plannedWork: [String]
            let workingSetCount: Int
            let changesSinceLastTime: [String]
            let lastPlannedWork: [String]?
            let lastLoggedWork: [String]?
            let workingSetCountChange: Int?
        }

        init(preview: WorkoutPreview, program: Program, workout: Workout, timingTitle: String,
             achievement: WorkoutAchievement?, history: WorkoutPreviewHistory? = nil, unit: WeightUnit = .current,
             at date: Date = .now) {
            self.program = program.templateName
            trainingStyle = preview.type.name
            phase = preview.weekKind?.rawValue ?? "standard"
            timing = timingTitle
            week = program.weekNumber(containing: workout)
            day = workout.order + 1
            focus = program.templateMuscleFocus.map(\.rawValue)
            self.achievement = achievement
            self.unit = unit
            weeks = program.programLengthWeeks
            daysPerWeek = program.workoutsPerWeek
            let observed = history ?? WorkoutPreviewHistory(rows: HistoryExport.rows(for: program), now: date)
            exercises = preview.lifts.map { lift in
                let planned = lift.sets.map {
                    [$0.role.title, $0.text(unit: unit)].compactMap { $0 }.joined(separator: " ")
                }
                let rows = observed.previousSets(for: lift, before: date)
                let pastPlan = rows.isEmpty ? nil : rows.map {
                    Self.setText(reps: $0.targetReps, weight: $0.targetWeightTenthsPounds, unit: unit)
                }
                let logged = rows.filter { WorkoutPreviewHistory.wasLogged($0, by: date) }
                let pastActual = rows.isEmpty ? nil : logged.map {
                    Self.setText(reps: $0.reps, weight: $0.weightTenthsPounds, unit: unit)
                }
                let count = lift.sets.reduce(0) { $0 + $1.count }
                let loggedLoads = logged.compactMap(\.weightTenthsPounds)
                let newLoad = lift.sets.compactMap(\.weight).max()
                var changes: [String] = []
                if let last = rows.first, WorkoutPreviewHistory.wasLogged(last, by: date),
                   let actual = last.reps, let next = lift.sets.first?.reps, next != actual {
                    changes.append("First working set goes from \(actual) logged reps to \(next) planned reps.")
                }
                if let last = loggedLoads.max(), let newLoad, newLoad != last {
                    let direction = newLoad > last ? "higher" : "lower"
                    changes.append("Heaviest working weight is \(direction): \(unit.format(tenthsPounds: last)) to \(unit.format(tenthsPounds: newLoad)) \(unit.symbol).")
                }
                return Lift(exercise: lift.name, muscle: lift.muscle.rawValue, plannedWork: planned,
                            workingSetCount: count, changesSinceLastTime: changes, lastPlannedWork: pastPlan, lastLoggedWork: pastActual,
                            workingSetCountChange: pastPlan.map { count - $0.count })
            }
        }

        private static func setText(reps: Int?, weight: Int?, unit: WeightUnit) -> String {
            let count = reps.map { "\($0) reps" } ?? "reps unspecified"
            return weight.map { "\(count) at \(unit.format(tenthsPounds: $0)) \(unit.symbol)" } ?? count
        }

        var prompt: String {
            var lines = [
                "\(timing). \(program), \(trainingStyle) program, \(phase) phase, day \(day) of \(daysPerWeek).",
                "Program focus: \(focus.joined(separator: ", "))."
            ]
            if let week { lines.append("Week \(week) of \(weeks).") }
            for lift in exercises {
                lines.append("Exercise: \(lift.exercise). Muscle: \(lift.muscle). Planned working sets: \(lift.workingSetCount). Prescription: \(lift.plannedWork.joined(separator: "; ")).")
                if let previous = lift.lastPlannedWork {
                    lines.append("Previous planned working sets: \(previous.count). Previous prescription: \(previous.joined(separator: "; ")).")
                    lines.append("Previously logged: \(lift.lastLoggedWork?.joined(separator: "; ") ?? "").")
                } else {
                    lines.append("No previous completed session for comparison.")
                }
                if let previous = lift.lastPlannedWork?.count, let delta = lift.workingSetCountChange, delta != 0 {
                    lines.append("Verified change: \(lift.exercise) goes from \(previous) to \(lift.workingSetCount) working sets.")
                }
                for change in lift.changesSinceLastTime { lines.append("Verified change: \(change)") }
            }
            return lines.joined(separator: "\n")
        }

        var achievementContext: String? {
            guard let achievement else { return nil }
            var lines = [achievement.title]
            switch achievement.kind {
            case .extraSet:
                if let old = achievement.previous, let new = achievement.target {
                    lines.append("Sets last time: \(old). Sets this time: \(new). Extra sets: \(new - old).")
                }
            case .strengthPR:
                lines.append("A PR is possible if the lifter hits the target.")
            case .repPR:
                lines.append("The lifter has a shot at a rep PR at the same load.")
            default:
                lines.append(achievement.detail(unit: unit))
            }
            if let name = achievement.exerciseName { lines.append("Exercise: \(name).") }
            if let weight = achievement.weight {
                lines.append("Weight: \(unit.format(tenthsPounds: weight)) \(unit.symbol).")
            }
            return lines.joined(separator: "\n")
        }

        var fingerprint: String {
            SHA256.hash(data: Data("trainer-achievements-v7\n\(prompt)\n\(achievementContext ?? "")".utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
    }

    static func generate(for facts: Facts) async -> String? {
        guard !facts.exercises.isEmpty, SystemLanguageModel.default.isAvailable else { return nil }
        let voice = """
            Write the way someone texts about the next lift: short, direct, friendly. Say the one
            thing the lifter would want to know, then stop. Use contractions and everyday lift names
            like bench or leg press. Keep the variation if it matters. Usually a dozen words is plenty.
            Talk to the lifter as "you". An occasional "we" is fine. This is one person's workout.
            Their plan is the only source of facts. Skip the pep-talk ending, slogans, and em dashes.
            """
        let summaryInstructions = """
            What's worth pointing out from the program, exercises, weights, last workout, and selected opportunity? Use that to write a brief, casual notification. A flagged opportunity should be described as something within reach; otherwise explain how the workout flows. Only use supplied facts and never claim an upcoming achievement is complete. PR references may include weight but not rep or set counts. No invented partner, jargon-heavy phrasing, anatomy lecture, or motivational closer.
            """
        var context = facts.prompt
        var revision: String?
        if let achievement = facts.achievement, let opportunity = facts.achievementContext {
            context += "\nPowerJack flagged this achievement for the next lift:\n\(opportunity)"
            revision = "Text the lifter one short sentence about this achievement: \(opportunity)"
            if achievement.kind == .strengthPR || achievement.kind == .repPR {
                let prRule = "Name the exercise and the shot at a PR. Weight is optional. Omit reps, sets and estimates."
                context += "\n" + prRule
                revision = "Write one sentence. \(prRule)\n\(opportunity)"
            }
        }
        if let event = facts.achievement, event.kind == .extraSet, let name = event.exerciseName,
           let old = event.previous, let new = event.target {
            let added = new - old
            let instruction = """
                Exercise: \(name). Added sets: \(added). Mention only the extra work this lifter has.
                Say "one more set" for an increase of one. Use the lift's everyday name and, if useful,
                the time from the title. The set change is the whole sentence. End with a period.
                """
            revision = instruction
            context += "\n" + instruction
        } else if facts.achievement?.kind == .firstProgram {
            context += "\nThis is the FINAL workout of the entire program. Finishing it would complete the lifter’s first full program."
        }
        guard let summary = await sentence(instructions: summaryInstructions, context: context, revision: revision,
                                           limit: facts.achievement == nil ? 260 : 150,
                                           valid: { text in
                                               guard validSummary(text, for: facts) else { return false }
                                               if let event = facts.achievement, event.kind == .extraSet {
                                                   return coversAchievement(text, for: event, unit: facts.unit)
                                               }
                                               return true
                                           }) else { return nil }
        guard let achievement = facts.achievement, let opportunity = facts.achievementContext,
              !coversAchievement(summary, for: achievement, unit: facts.unit) else { return summary }

        let cheerInstructions = """
            \(voice)
            They've already read the summary. Give them one short line about the specific opportunity.
            Say what completing this lift would mean for them. Use the flagged achievement and name
            the exercise when relevant. Keep encouragement specific to what they could do. End there.
            """
        let isExercisePR = achievement.kind == .strengthPR || achievement.kind == .repPR
        let rules = isExercisePR
            ? "Name the exercise and the PR opportunity. You can say 'rep PR' for a rep record. Only its target weight may appear as a number. Leave out set counts, rep counts, workout notation and how the record was calculated."
            : "Use numbers only when supplied in the opportunity. Focus on this single achievement."
        let input = "Workout summary: \(summary)\nOpportunity: \(opportunity)\n\(rules)"
        guard let cheer = await sentence(instructions: cheerInstructions, context: input, limit: 259 - summary.count,
                                         valid: { validCheer($0, for: achievement, unit: facts.unit) }) else { return nil }
        return "\(summary) \(cheer)"
    }

    static func validSummary(_ text: String, for facts: Facts) -> Bool {
        guard !matches(#"\b(planned working sets?|as always|as usual|like always|worth previewing|(?:session|workout|lift) matters because)\b"#, text),
              !misstatesFirstProgram(text),
              !isAnatomyExplanation(text), !isUngroundedOrSlogan(text) else { return false }
        let conflictingTime = facts.timing.localizedCaseInsensitiveContains("tomorrow") ? #"\b(today|tonight)\b"# : #"\btomorrow\b"#
        guard !matches(conflictingTime, text) else { return false }
        if let achievement = facts.achievement {
            if achievement.kind == .firstProgram && creditsOneSetForProgram(text) { return false }
            if coversAchievement(text, for: achievement, unit: facts.unit) { return true }
            // A partial milestone claim gets a rewrite. Only a neutral summary can receive a separate cheer.
            if mentionsAchievement(text, kind: achievement.kind) { return false }
        }
        // Even if another sentence would clarify the opportunity, never ship a false or premature PR claim.
        guard !mentionsPR(text), !claimsCompletion(text) else { return false }
        if facts.exercises.contains(where: { refersToExercise($0.exercise, in: text) }) { return true }
        let focus = Set(facts.exercises.map(\.muscle) + facts.focus)
        return focus.contains { muscle in
            guard let terms = muscleTerms[muscle] else { return false }
            return matches(#"\b(?:"# + terms + #")\b"#, text)
        }
    }

    private static let muscleTerms = [
        "chest": "chest|pecs?|pectorals?", "back": "back|lats?|traps?", "shoulders": "shoulders?|delts?|deltoids?",
        "biceps": "biceps?|arms?", "triceps": "triceps?|arms?", "quads": "quads?|quadriceps|legs?",
        "glutes": "glutes?|hips?|legs?", "hamstrings": "hamstrings?|legs?", "calves": "calf|calves|legs?",
        "abs": "abs|abdominals?|core", "obliques": "obliques?|core", "forearms": "forearms?|grip"
    ]

    private static func isAnatomyExplanation(_ text: String) -> Bool {
        let muscles = "(?:" + muscleTerms.values.joined(separator: "|") + ")"
        let explanation = #"\b(?:is (?:great |good )?for|target(?:s|ing)?|work(?:s|ing)?|train(?:s|ing)?|hit(?:s|ting)?|isolat(?:e|es|ing)|strengthen(?:s|ing)?|build(?:s|ing)?|focus(?:es|ing)? on) (?:your |the |those )?(?:upper |lower )?"#
        return matches(explanation + muscles + #"\b(?! (?:press|extension|curl|raise)s?\b)"#, text)
            || matches(#"\("# + muscles + #"\)"#, text)
    }

    private static func isUngroundedOrSlogan(_ text: String) -> Bool {
        // The input only describes this lifter. It contains no information about a partner.
        if matches(#"\b(?:partner|buddy|spotter|teammate)(?:s|['’]s)?\b"#, text) { return true }
        let stock = #"\b(?:(?:we|you)(?:['’]ve| have)? got this|let['’]s make it count|crush it|kill it|you['’]re crushing it)\b"#
        return matches(stock, text) || matches(#"\blet['’]s go(?=\s*(?:$|[.,!?;:—–-]))"#, text)
    }

    /// Single-sentence delivery requires the selected event itself, not just the same lift or a generic cheer.
    static func coversAchievement(_ text: String, for achievement: WorkoutAchievement, unit: WeightUnit) -> Bool {
        let normalized = normalizedNumbers(in: text)
        guard validCheer(text, for: achievement, unit: unit) else { return false }
        if let name = achievement.exerciseName, !refersToExercise(name, in: text) { return false }
        switch achievement.kind {
        case .firstProgram:
            return matches(#"\b(first|1st)\b"#, text) && matches(#"\bprogram(?:me)?\b"#, text)
                && matches(#"\b(finish(?:es|ing)?|complet(?:e|es|ing|ion)|wrap(?:s|ping)? up|close(?:s)? out|last|final)\b"#, text)
        case .fourWeekStreak:
            return matches(#"\b4[- ](?:straight |consecutive )?(?:program )?weeks?\b|\bfourth (?:straight |consecutive )?(?:program )?week\b"#, normalized)
                && matches(#"\b(streak|straight|consecutive|in a row|unbroken)\b"#, text)
        case .returnToBest:
            if matches(#"\bstrongest\b"#, text), matches(#"\b(?:back to|after (?:a |the |some )?(?:break|time away|time off))\b"#, text) { return true }
            return matches(#"\b(previous|old|prior|former|best|peak)\b"#, text)
                && matches(#"\b(match(?:ing)?|return(?:ing)?|back|reclaim(?:ing)?|regain(?:ing)?|again)\b"#, text)
                && matches(#"\b(best|record|PR|PB|peak)\b"#, text)
        case .strengthPR, .repPR:
            guard matches(#"\b(could|would|can|chance|shot|possible|potential|aim|try|chase|in play|in reach|within reach|on the (?:table|line)|go for|go get|let[’']s (?:get|catch|go for))\b"#, text) else { return false }
            return achievement.kind == .strengthPR || matches(#"\brep(?:etition)?[- ](?:PR|PB|record|personal best)\b"#, text)
        case .sessionVolume:
            return matches(#"\b(volume|tonnage|workload|total (?:weight|load)|weight lifted)\b"#, text)
                && matches(#"\b(record|best|biggest|highest|most|beat|surpass|exceed|top)\b"#, text)
        case .heavierDumbbells:
            guard matches(#"\bdumbbells?\b"#, text) else { return false }
            if matches(#"\b(heavier|heaviest|move up|step up|up from)\b"#, text) { return true }
            guard let weight = achievement.weight else { return false }
            let target = NSRegularExpression.escapedPattern(for: unit.format(tenthsPounds: weight))
            let units = unit == .kilograms ? "(?:kg|kilograms?)" : "(?:lbs?|pounds?)"
            return matches(#"\b(?:jumps?|moves?|steps?|goes|going|increases?|bump(?:s|ing)?) (?:up )?to "# + target + #"[- ]*"# + units + #"\b"#, text)
        case .extraSet:
            guard let old = achievement.previous, let new = achievement.target else { return false }
            let sets = #" (?:(?:planned|working) )*sets?\b"#
            let forward = #"\b"# + String(old) + #"(?:"# + sets + #")? (?:up )?to "# + String(new) + sets
            let reverse = #"\b"# + String(new) + sets + #" (?:instead of|rather than|up from|from) "# + String(old) + #"\b"#
            if matches(forward, normalized) || matches(reverse, normalized) { return true }
            let added = new - old
            if added > 1 {
                return matches(#"\b"# + String(added) + #" (?:more|extra|additional) sets?\b"#, normalized)
                    && normalized.matches(of: /\d+/).count == 1
            }
            guard added == 1 else { return false }
            let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
            if (1...ordinals.count).contains(new),
               matches(#"\b(?:add|gain)(?:s|ing)? (?:a |the |that )?"# + ordinals[new - 1] + #" (?:working )?set\b"#, normalized) { return true }
            // An explicit total must match the prescription as well as the stated one-set increase.
            let single = normalized.replacingOccurrences(of: #"(?i)\b1 (more|extra|additional)\b"#, with: "$1", options: .regularExpression)
            let remainder = single.replacingOccurrences(of: #"(?i)\b"# + String(new) + sets, with: "", options: .regularExpression)
            return !remainder.contains(where: \.isNumber)
                && matches(#"\b(?:extra|additional|another|more) (?:working )?set\b|\badd(?:s|ing)? (?:a|an extra) (?:working )?set\b"#, single)
        }
    }

    private static func mentionsAchievement(_ text: String, kind: WorkoutAchievement.Kind) -> Bool {
        let pattern: String
        switch kind {
        case .firstProgram: pattern = #"\b(?:program|programme)\b.*\b(?:first|final|complete|finish)|\b(?:first|final|complet\w*|finish\w*|wrap\w* up)\b.*\bprogram(?:me)?\b"#
        case .fourWeekStreak: pattern = #"\b(?:streak|consecutive|straight weeks?|weeks? in a row|four[- ]weeks?|fourth week|4[- ]weeks?)\b"#
        case .returnToBest: pattern = #"\b(?:best|strongest|peak|comeback|return to form)\b"#
        case .strengthPR, .repPR: pattern = #"\b(?:best|record|PR|PB)s?\b"#
        case .sessionVolume: pattern = #"\b(?:volume|tonnage|workload|total (?:weight|load)|weight lifted|biggest session)\b"#
        case .heavierDumbbells: pattern = #"\b(?:heavier|heaviest|heavy pair|steps? up|moves? up|jumps? to)\b"#
        case .extraSet: pattern = #"\bsets?\b"#
        }
        return matches(pattern, text)
    }

    private static func normalizedNumbers(in text: String) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return text.replacing(/(?i)\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b/) { match in
            String(words.firstIndex(of: match.output.lowercased())!)
        }
    }

    private static func misstatesFirstProgram(_ text: String) -> Bool {
        matches(#"\b(?:first|1st) (?:full )?program(?:me)?(?:’s|'s)? (?:session|workout|day|week)\b"#, text)
    }

    private static func creditsOneSetForProgram(_ text: String) -> Bool {
        matches(#"\b(?:finish(?:ing)?|complet(?:e|ing)|log(?:ging)?|hit(?:ting)?) (?:this|that|the|one|your) (?:last |final )?set\b.*\b(?:program|sessions?|workouts?)\b"#, text)
    }

    private static func claimsCompletion(_ text: String) -> Bool {
        matches(#"\b(already|congratulations|congrats)\b|\byou(?:’ve|'ve| have| just) (?:set|finished|hit|earned|beaten|broken|completed|achieved|reached|nailed|crushed)\b|\byou (finished|earned|beat|broke|completed|achieved|reached|nailed|crushed)\b|(?:^|[,;]\s*)you (hit|set|got) (?:a |your |the |that )?(?:new |first |fourth )?(?:PR|PB|record|personal best|streak|milestone)\b|\b(you did it|in the books|in the bag|mission accomplished)\b"#, text)
    }

    static func validCheer(_ text: String, for achievement: WorkoutAchievement, unit: WeightUnit) -> Bool {
        guard !claimsCompletion(text), !misstatesFirstProgram(text), !isUngroundedOrSlogan(text), !matches(#"\b(estimated|e1rm)\b"#, text) else { return false }
        if achievement.kind == .strengthPR || achievement.kind == .repPR {
            guard let name = achievement.exerciseName else { return false }
            let target = achievement.weight.map { "\(unit.format(tenthsPounds: $0)) \(unit.symbol)" }
            return validPRCheer(text, weight: target, exerciseName: name, repRecord: achievement.kind == .repPR)
        }
        if mentionsPR(text) {
            let volume = achievement.kind == .sessionVolume && matches(#"\b(volume|tonnage|workload)\b"#, text)
            let returning = achievement.kind == .returnToBest && matches(#"\b(previous|prior|old|former)\b"#, text)
            guard volume || returning else { return false }
        }
        let signal: String
        switch achievement.kind {
        case .firstProgram:
            guard !creditsOneSetForProgram(text), matches(#"\bprogram(?:me)?\b"#, text) else { return false }
            signal = #"\b(first|finish|complete|completion|wrap)\b"#
        case .fourWeekStreak: signal = #"\b(streak|weeks?|straight|consecutive)\b"#
        case .returnToBest:
            guard matches(#"\b(best|strongest|peak|record|PR|PB)\b"#, text) else { return false }
            signal = #"\b(back to|back at|back up to|return(?:ing)?|match(?:ing)?|reclaim(?:ing)?|regain(?:ing)?|again|comeback|after a break|after time away|after time off)\b"#
        case .sessionVolume: signal = #"\b(volume|tonnage|workload|total|record|biggest|most)\b"#
        case .heavierDumbbells: signal = #"\b(heavier|dumbbells?|pair|step up|move up)\b"#
        case .extraSet: signal = #"\bsets?\b"#
        case .strengthPR, .repPR: return false
        }
        guard matches(signal, text) else { return false }
        let allowed = achievement.detail(unit: unit) + " " + achievement.title
        let numbers = text.matches(of: /\d+(?:[.,]\d+)?/).map { String($0.output) }
        var verified = Set(allowed.matches(of: /\d+(?:[.,]\d+)?/).map { String($0.output) })
        if achievement.kind == .fourWeekStreak { verified.insert("4") }
        if achievement.kind == .extraSet, let old = achievement.previous, let new = achievement.target {
            verified.insert(String(new - old))
        }
        return numbers.allSatisfy(verified.contains)
    }

    static func validPRCheer(_ text: String, weight: String?, exerciseName: String = "bench", repRecord: Bool = false) -> Bool {
        guard mentionsPR(text), refersToExercise(exerciseName, in: text),
              !matches(#"\b(estimated|e1rm)\b"#, text) else { return false }
        // "Set a new PR" is encouragement. "One set" and "three reps" prescribe work.
        let prescription = #"\b(reps?|repetitions?|sets|singles?|doubles?|triples?|amrap|top[- ]set|back[- ]off|working[- ]set|last set|final set)\b|\b(a|one|two|three|your|this|that|each|every|per) set\b|\bfor (one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#
        let withoutRecordLabel = repRecord
            ? text.replacingOccurrences(of: #"(?i)\brep(?:etition)?[- ]+(?:PR|PB|record|personal best)\b"#,
                                        with: "", options: .regularExpression)
            : text
        guard !matches(prescription, withoutRecordLabel) else { return false }
        let weightUnit = #"\b(lbs?|pounds?|kg|kilograms?)\b"#
        guard let weight else { return !text.contains(where: \.isNumber) && !matches(weightUnit, text) }
        let amount = NSRegularExpression.escapedPattern(for: String(weight.prefix { !$0.isWhitespace }))
        let unit = weight.hasSuffix("kg") ? "(?:kg|kilograms?)" : "(?:lbs?|pounds?)"
        let withoutWeight = text.replacingOccurrences(of: #"(?i)(?<![\d.,])"# + amount + #"[\s-]*"# + unit + #"\b"#,
                                                      with: "", options: .regularExpression)
        return !withoutWeight.contains(where: \.isNumber) && !matches(weightUnit, withoutWeight)
    }

    private static func refersToExercise(_ name: String, in text: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }
        let equipment: Set<Substring> = ["barbell", "dumbbell", "machine", "cable", "with", "the"]
        let movement = words.filter { !equipment.contains($0) }
        // "Bench" alone is common; "press" alone could mean the leg press.
        if movement == ["bench", "press"] { return matches(#"\bbench(?:ing)?\b"#, text) }
        let terms = movement.isEmpty ? words : movement
        let messageWords = text.lowercased().split { !$0.isLetter }
        return !terms.isEmpty && terms.allSatisfy { term in
            messageWords.contains(term) || messageWords.contains(Substring(term + "s"))
        }
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: "(?i)" + pattern, options: .regularExpression) != nil
    }

    private static func mentionsPR(_ text: String) -> Bool {
        matches(#"\b(PR|PB|record|personal[- ]best|strength best)s?\b"#, text)
    }

    private static func sentence(instructions: String, context: String, revision: String? = nil, limit: Int,
                                 valid: (String) -> Bool) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        var request = context
        for _ in 0..<2 {
            guard !Task.isCancelled, let reply = try? await session.respond(to: request) else { return nil }
            let text = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = text
            if let last = text.last, ".!".contains(last), text.contains(where: \.isLetter),
               text.count <= limit, !text.contains(where: \.isNewline),
               !matches(#"\b(output just|as an ai|the supplied|the named exercise|the workout summary|in one (short )?sentence)\b"#, text),
               tokenizer.tokens(for: text.startIndex..<text.endIndex).count == 1, valid(text) { return text }
            request = revision ?? "Rewrite as a short text to the lifter using just one concrete fact, in twelve words or fewer. Follow the original instructions. Return only the sentence."
        }
        return nil
    }
}
