//
//  EmptyStateView.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
    }
}
