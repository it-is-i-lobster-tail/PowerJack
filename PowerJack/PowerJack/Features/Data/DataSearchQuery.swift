import Foundation

/// A trailing calendar date can narrow any Data search.
struct DataSearchQuery {
    let exerciseText: String
    let dateFilter: WorkoutDateFilter?

    init(_ text: String) {
        var words = text.split(whereSeparator: \.isWhitespace)
        let year = Self.takeYear(from: &words)
        if let last = words.last, let month = Self.monthNumbers[Self.normalize(last)] {
            words.removeLast()
            dateFilter = .month(month, year: year ?? Self.takeYear(from: &words))
        } else if words.count >= 2, let last = words.last,
                  let day = Int(Self.normalize(last)), (1...31).contains(day),
                  let month = Self.monthNumbers[Self.normalize(words[words.count - 2])] {
            words.removeLast(2)
            dateFilter = .day(day, month: month, year: year)
        } else {
            dateFilter = year.map(WorkoutDateFilter.year)
        }
        if dateFilter != nil, let last = words.last, ["in", "from", "during", "on"].contains(last.lowercased()) {
            words.removeLast()
        }
        exerciseText = dateFilter == nil ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }

    private static func takeYear(from words: inout [Substring]) -> Int? {
        guard let last = words.last else { return nil }
        let token = normalize(last)
        guard token.count == 4, let year = Int(token), (1000...9999).contains(year) else { return nil }
        words.removeLast()
        return year
    }

    private static func normalize(_ word: some StringProtocol) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func monthNumber(_ word: some StringProtocol) -> Int? {
        monthNumbers[normalize(word)]
    }

    private static let monthNumbers: [String: Int] = {
        var calendar = Calendar(identifier: .gregorian)
        var numbers: [String: Int] = [:]
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "en_GB"), .current] {
            calendar.locale = locale
            for names in [calendar.monthSymbols, calendar.shortMonthSymbols,
                          calendar.standaloneMonthSymbols, calendar.shortStandaloneMonthSymbols] {
                for (index, name) in names.enumerated() {
                    numbers[normalize(name)] = index + 1
                }
            }
        }
        // Once a month is recognized, completing its name should keep the same filter.
        var prefixes: [String: Set<Int>] = [:]
        for (name, month) in numbers where name.count > 3 {
            for length in 3..<name.count {
                prefixes[String(name.prefix(length)), default: []].insert(month)
            }
        }
        for (prefix, months) in prefixes where months.count == 1 && numbers[prefix] == nil {
            numbers[prefix] = months.first
        }
        return numbers
    }()
}
