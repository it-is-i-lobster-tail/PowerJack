//
//  TemplateBuilderHint.swift
//  PowerJack
//

import SwiftUI

/// Shown above a template's exercises until the lifter edits or adds one.
struct TemplateBuilderHint: Hint {
    var title: Text { Text("Edit any exercise or add your own custom ones.") }
}
