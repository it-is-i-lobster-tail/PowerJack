//
//  SharedFileLink.swift
//  PowerJack
//

import SwiftUI

/// The Share button for a template or exercise: AirDrop, Messages, Mail, Save to Files and the rest.
struct SharedFileLink: View {
    let file: SharedFile

    var body: some View {
        if let item = try? file.item() {
            ShareLink(item: item, preview: SharePreview(item.name)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
