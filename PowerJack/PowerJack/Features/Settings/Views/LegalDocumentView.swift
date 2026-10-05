//
//  LegalDocumentView.swift
//  PowerJack
//

import SwiftUI

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Last updated \(document.lastUpdated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(document.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                        Text(section.heading)
                            .font(.headline)
                        Text(section.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Terms") {
    NavigationStack {
        LegalDocumentView(document: .termsAndConditions)
    }
}
