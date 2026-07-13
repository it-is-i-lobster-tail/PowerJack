//
//  Exercise+New.swift
//  PowerJack
//
//  Created by Brendon on 7/5/26.
//

import SwiftData
import SwiftUI
import OSLog

struct ExerciseNew: View {    
    @State private var draft = ExerciseDraft()
    
    let onSave: (Exercise) -> Void
    
    var body: some View {
        ExerciseForm(
            draft: $draft,
            onSave: onSave
        )
        .navigationTitle("New Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("ExerciseNew - Default") {
    NavigationStack {
        ExerciseNew(onSave: { _ in })
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
