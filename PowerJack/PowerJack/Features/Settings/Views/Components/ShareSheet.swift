//
//  ShareSheet.swift
//  PowerJack
//
//  The system share sheet for a file: AirDrop, Mail, Save to Files and the rest.
//  SwiftUI's ShareLink opens it straight away, and the history export asks first.
//

import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
