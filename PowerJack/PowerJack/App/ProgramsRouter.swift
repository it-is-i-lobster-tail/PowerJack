//
//  ProgramsRouter.swift
//  PowerJack
//
//  Navigation state for the Programs tab.
//

import SwiftData
import SwiftUI

enum ProgramRoute: Hashable {
    case newProgram
    case detail(Program)
    case session(Program)
}

@Observable
final class ProgramsRouter {
    var path: [ProgramRoute] = []
    /// Bumped to ask the open workout to scroll back to its current exercise.
    private(set) var currentExerciseRequest = 0

    func showNewProgram() {
        path.append(.newProgram)
    }

    func showDetail(_ program: Program) {
        path.append(.detail(program))
    }

    func showSession(_ program: Program) {
        path.append(.session(program))
    }

    /// Opens the active program: straight into its workout if one is underway, otherwise its detail page.
    func restore(activeProgram: Program) {
        if activeProgram.nextWorkout?.status == .active {
            path = [.detail(activeProgram), .session(activeProgram)]
        } else {
            showDetailOnly(activeProgram)
        }
    }

    /// Leaves just the program's detail page, where Start Workout begins the next workout.
    func showDetailOnly(_ program: Program) {
        path = [.detail(program)]
    }

    /// Opens the active program's workout on the exercise the user should be doing now.
    func showCurrentExercise(of activeProgram: Program) {
        let sessionPath: [ProgramRoute] = [.detail(activeProgram), .session(activeProgram)]
        if path != sessionPath {
            path = sessionPath
        }
        currentExerciseRequest += 1
    }

    func popToRoot() {
        path.removeAll()
    }
}

extension View {
    /// Registers the destinations for every `ProgramRoute`.
    func programRouteDestinations() -> some View {
        navigationDestination(for: ProgramRoute.self) { route in
            switch route {
            case .newProgram:
                ProgramNew()
            case .detail(let program):
                ProgramDetailView(program: program)
            case .session(let program):
                ProgramSessionView(program: program)
            }
        }
    }
}
