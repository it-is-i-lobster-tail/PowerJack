import Foundation
import FoundationModels

@Generable
private struct GeneratedPreviewCopy {
    @Guide(description: "One playful, friendly sentence about this lift, at most 90 characters.")
    var tagline: String

    @Guide(description: "The zero-based index of the supplied factual focus sentence that fits best.")
    var focusIndex: Int
}

enum WorkoutPreviewCopy {
    struct Copy: Codable, Equatable {
        let tagline: String
        let focus: String
    }

    private struct SavedCopy: Codable {
        let key: String
        let copy: Copy
    }

    private static let cacheKey = "workoutPreview.generatedCopy"

    static func fallback(for preview: WorkoutPreview, variation: Int) -> Copy {
        let lines: [String]
        if preview.weekKind == .deload {
            lines = ["A lighter lift still counts. The plates can take a breather.", "Even dumbbells get a slow day."]
        } else {
            switch preview.mainMuscle {
            case .quads, .glutes, .hamstrings, .calves:
                lines = ["Stairs will be hard after this leg day.", "Your legs have plans."]
            case .back:
                lines = ["Big back day coming up!", "The rows are calling."]
            case .biceps, .triceps, .forearms:
                lines = ["Suns out, guns out kinda lift.", "The sleeves had a good run."]
            default:
                lines = ["Begin hydrating now.", "The dumbbells missed you."]
            }
        }
        return Copy(tagline: lines[variation % lines.count], focus: preview.focusOptions[0])
    }

    @MainActor
    static func generate(for preview: WorkoutPreview, workoutID: UUID?, variation: Int) async -> Copy? {
        // Only built-in exercise names are passed through as model input.
        let lifts = preview.lifts.prefix(5).map { lift in
            lift.catalogID == nil ? lift.muscle.rawValue : lift.name
        }.joined(separator: ", ")
        let focusOptions = preview.focusOptions
        let key = [
            workoutID?.uuidString ?? "", preview.type.rawValue, preview.weekKind?.rawValue ?? "",
            lifts, focusOptions.joined(separator: "|")
        ].joined(separator: "\n")

        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let saved = try? JSONDecoder().decode(SavedCopy.self, from: data), saved.key == key {
            return saved.copy
        }
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            Write like a goofy gym buddy. Be kind and keep it short. Skip emojis, hashtags, body judgments, \
            medical claims, predictions of injury, and advice to change the workout. \
            Keep all facts grounded in the supplied session. Do not make up exercises or targets.
            """)
        let angles = ["a wry one-liner", "a tiny pep talk", "an exaggerated but friendly gym joke"]
        let response = try? await session.respond(to: """
            Program: \(preview.type.name)
            Phase: \(preview.weekKind?.rawValue ?? "standard")
            Main lifts: \(lifts)
            Main muscle: \(preview.mainMuscle?.rawValue ?? "mixed")
            Focus options in order: \(focusOptions.count) choices, starting at zero. \
            First choice is the exercise order. If there's a second choice, it includes the muscle emphasis.
            Tagline style: \(angles[variation % angles.count])
            """, generating: GeneratedPreviewCopy.self)
        guard !Task.isCancelled, let response else { return nil }

        let result = response.content
        let line = result.tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...90).contains(line.count), line.rangeOfCharacter(from: .newlines) == nil,
              focusOptions.indices.contains(result.focusIndex) else { return nil }
        let copy = Copy(tagline: line, focus: focusOptions[result.focusIndex])
        if let data = try? JSONEncoder().encode(SavedCopy(key: key, copy: copy)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        return copy
    }

    static func variation(for id: UUID?) -> Int {
        (id?.uuidString.utf8.reduce(0) { $0 + Int($1) } ?? 0)
    }
}
