//
//  LegalSettingsView.swift
//  PowerJack
//
//  The privacy policy and the terms.
//

import SwiftUI

struct LegalSettingsView: View {
    var body: some View {
        content.traceScreen("Legal")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                NavigationLink {
                    LegalDocumentView(document: .privacyPolicy)
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                NavigationLink {
                    LegalDocumentView(document: .termsAndConditions)
                } label: {
                    Label("Terms and Conditions", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Legal") {
    NavigationStack { LegalSettingsView() }
}
