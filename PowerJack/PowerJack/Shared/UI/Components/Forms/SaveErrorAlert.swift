//
//  SaveErrorAlert.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

extension View {
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Unable to Save",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        message.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                message.wrappedValue = nil
            }
        } message: {
            Text(message.wrappedValue ?? "Please try again.")
        }
    }
}
