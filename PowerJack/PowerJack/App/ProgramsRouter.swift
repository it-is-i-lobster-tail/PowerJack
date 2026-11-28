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
    case preview(Program, Workout, WorkoutReminders.Highlight?)
    case completedWorkout(Program, Workout)
    case editDays(Program)

    /// True once syncing has deleted the program or workout this route shows, for example when
    /// the tidy-up folds the watch's copy into the iPhone's. Such a model can't be read any more.
    var showsRemovedModel: Bool {
        let models: [any PersistentModel] = switch self {
        case .newProgram: []
        case .detail(let program), .session(let program), .editDays(let program): [program]
        case .preview(let program, let workout, _), .completedWorkout(let program, let workout): [program, workout]
        }
        return models.contains { $0.isDeleted || $0.modelContext == nil }
    }
}

@Observable
final class ProgramsRouter {
    var path: [ProgramRoute] = []
    /// Bumped to ask the open workout to scroll back to its current exercise.
    private(set) var currentExerciseRequest = 0
    /// Retain the destination until the live workout appears, including when the timer opens it from another tab.
    @ObservationIgnored private var requestedWorkoutID: PersistentIdentifier?

    func showNewProgram() {
        path.append(.newProgram)
    }

    func showDetail(_ program: Program) {
        path.append(.detail(program))
    }

    func showSession(_ program: Program) {
        path.append(.session(program))
    }

    func showPreview(_ workout: Workout, in program: Program, highlight: WorkoutReminders.Highlight? = nil) {
        path = [.detail(program), .preview(program, workout, highlight)]
    }

    func showEditDays(_ program: Program) {
        path.append(.editDays(program))
    }

    /// Opens a workout from the progress grid: the active one resumes, a completed one opens read-only.
    func showWorkout(_ workout: Workout, in program: Program) {
        switch workout.status {
        case .active:
            showSession(program)
        case .complete:
            path.append(.completedWorkout(program, workout))
        default:
            break
        }
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
        requestedWorkoutID = activeProgram.nextWorkout?.persistentModelID
        let sessionPath: [ProgramRoute] = [.detail(activeProgram), .session(activeProgram)]
        if path != sessionPath {
            path = sessionPath
        }
        currentExerciseRequest += 1
    }

    /// Resolve against the current set so the member stays correct if a superset was reordered.
    func requestedExerciseIndex(in workout: Workout) -> Int? {
        guard requestedWorkoutID == workout.persistentModelID else { return nil }
        if let next = workout.currentSet?.workoutExercise,
           let index = workout.workoutExercises.firstIndex(of: next) {
            return index
        }
        return workout.allExercisesFinished ? workout.workoutExercises.count : workout.currentExerciseIndex
    }

    func didShowRequestedExercise() {
        requestedWorkoutID = nil
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Goes back to the last screen whose program and workout still exist.
    func dropRemovedRoutes() {
        guard let index = path.firstIndex(where: \.showsRemovedModel) else { return }
        path.removeSubrange(index...)
    }
}

extension View {
    /// Registers the destinations for every `ProgramRoute`.
    func programRouteDestinations() -> some View {
        modifier(ProgramRouteDestinations())
    }
}

private struct ProgramRouteDestinations: ViewModifier {
    @Environment(ProgramsRouter.self) private var router
    /// Bumped when a save deletes a model an open screen shows, so that screen is rebuilt as `RemovedRouteView`.
    @State private var removals = 0

    func body(content: Content) -> some View {
        let removals = removals
        content
            .navigationDestination(for: ProgramRoute.self) { route in
                let _ = removals
                if route.showsRemovedModel {
                    RemovedRouteView()
                } else {
                    destination(for: route)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                if router.path.contains(where: \.showsRemovedModel) { self.removals += 1 }
            }
    }

    @ViewBuilder
    private func destination(for route: ProgramRoute) -> some View {
        switch route {
        case .newProgram:
            ProgramNew()
        case .detail(let program):
            ProgramDetailView(program: program)
        case .session(let program):
            ProgramSessionView(program: program)
        case .preview(let program, let workout, let highlight):
            PreviewWorkoutView(program: program, workout: workout, highlight: highlight)
        case .completedWorkout(_, let workout):
            WorkoutDetailView(workout: workout, isReadOnly: true)
        case .editDays(let program):
            ProgramLayoutView(program: program)
        }
    }
}

/// Shown for a moment in place of a screen whose program or workout another device's changes replaced,
/// then goes back.
private struct RemovedRouteView: View {
    @Environment(ProgramsRouter.self) private var router

    var body: some View {
        ContentUnavailableView(
            "Updated on Another Device",
            systemImage: "arrow.triangle.2.circlepath",
            description: Text("This changed on your other device. Going back.")
        )
        .navigationBarBackButtonHidden()
        .task {
            TraceLog.record(.screen, "Programs: closed a screen whose model was removed by syncing")
            try? await Task.sleep(for: .seconds(1.5))
            router.dropRemovedRoutes()
        }
    }
}
