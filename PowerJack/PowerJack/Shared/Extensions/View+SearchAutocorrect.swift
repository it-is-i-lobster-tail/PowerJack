//
//  View+SearchAutocorrect.swift
//  PowerJack
//
//  Keeps autocorrect and spell checking on in search bars.
//

import SwiftUI

extension View {
    /// UIKit search bars, which `.searchable` uses, turn autocorrect off unless told otherwise.
    /// Apply after `.searchable` so misspelled words in a search are corrected as they are typed.
    func searchAutocorrects() -> some View {
        autocorrectionDisabled(false)
    }
}
