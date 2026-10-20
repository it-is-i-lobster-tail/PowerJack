//
//  WatchDemo.swift
//  PowerJackWatch
//
//  Simulators aren't signed in to iCloud, so debug builds can start a program on the watch
//  itself: launch with `-demoProgram hypertrophy`, `strength` or `powerjack`.
//  It runs in memory, so nothing is saved or synced.
//

#if DEBUG
import Foundation
import OSLog
import SwiftData

enum WatchDemo {
    static var requestedType: TemplateType? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoProgram"), arguments.indices.contains(index + 1) else { return nil }
        return TemplateType(rawValue: arguments[index + 1])
    }

    /// An in-memory store holding a started program of `type`, built from the first built-in template.
    static func makeContainer(type: TemplateType) -> ModelContainer {
        do {
            let container = try PowerJackSchema.makeModelContainer(inMemory: true)
            let context = container.mainContext
            try ExerciseCatalog.seed(in: context)
            try TemplateCatalog.seed(in: context)
            let template = try context.fetch(FetchDescriptor<TemplateProgram>())
                .filter { $0.templateType == type }
                .min { $0.templateName < $1.templateName }
            if let template {
                let program = Program(programLengthWeeks: 4, templateProgram: template)
                context.insert(program)
                program.start()
                try context.save()
            }
            return container
        } catch {
            fatalError("Could not build the demo program: \(error)")
        }
    }
}
#endif
