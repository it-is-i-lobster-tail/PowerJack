//
//  FormSubmitButton.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct FormSubmitButton: View {
    let title: LocalizedStringKey
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isEnabled ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
