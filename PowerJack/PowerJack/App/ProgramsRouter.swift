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

    func showNewProgram() {
        path.append(.newProgram)
    }

    func showDetail(_ program: Program) {
        path.append(.detail(program))
    }

    func showSession(_ program: Program) {
        path.append(.session(program))
    }

    /// Opens straight into the active program's current workout, keeping the detail page underneath.
    func restore(activeProgram: Program) {
        path = [.detail(activeProgram), .session(activeProgram)]
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
