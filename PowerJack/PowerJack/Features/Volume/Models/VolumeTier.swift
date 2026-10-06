//
//  VolumeTier.swift
//  PowerJack
//
//  What a muscle's weekly set count means for growth.
//  Colors come from the Okabe-Ito palette, which stays distinct with color blindness.
//

import SwiftUI

enum VolumeTier: CaseIterable, Identifiable {
    case tooLittle
    case maintenance
    case growth
    case maxGrowth
    case tooMuch

    var id: Self { self }

    /// Picks the tier from the average rounded to whole sets.
    init(weeklySets: Double) {
        switch Int(weeklySets.rounded()) {
        case ...2: self = .tooLittle
        case 3...5: self = .maintenance
        case 6...12: self = .growth
        case 13...25: self = .maxGrowth
        default: self = .tooMuch
        }
    }

    var name: String {
        switch self {
        case .tooLittle: "Too little"
        case .maintenance: "Maintenance"
        case .growth: "Growth"
        case .maxGrowth: "Max growth"
        case .tooMuch: "Too much"
        }
    }

    /// Weekly sets in this tier, e.g. "6–12".
    var setRange: String {
        switch self {
        case .tooLittle: "0–2"
        case .maintenance: "3–5"
        case .growth: "6–12"
        case .maxGrowth: "13–25"
        case .tooMuch: "26+"
        }
    }

    var color: Color {
        switch self {
        case .tooLittle: Color(uiColor: .systemGray3)
        case .maintenance: Color(uiColor: .systemGray)
        // Okabe-Ito bluish green.
        case .growth: Color(red: 0, green: 0.62, blue: 0.45)
        // Okabe-Ito blue, lightened to sky blue on dark backgrounds.
        case .maxGrowth: Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.34, green: 0.71, blue: 0.91, alpha: 1)
                : UIColor(red: 0, green: 0.45, blue: 0.70, alpha: 1)
        })
        // Okabe-Ito vermillion.
        case .tooMuch: Color(red: 0.84, green: 0.37, blue: 0)
        }
    }
}
