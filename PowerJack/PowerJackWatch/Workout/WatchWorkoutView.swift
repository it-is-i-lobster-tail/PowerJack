//
//  WatchWorkoutView.swift
//  PowerJackWatch
//
//  One page per exercise, with an overview for jumping to an exercise or finishing. Swiping moves between exercises;
//  logging an exercise's last set asks for its feedback, then moves on to the next one.
//  In a superset, logging a set moves to the exercise whose turn it is.
//

import SwiftData
import SwiftUI
import WatchKit

/// Sheets the workout presents for the exercise on screen.
private enum WorkoutSheet: Identifiable, Hashable {
    case overview
    case feedback(WorkoutExercise)
    case checkIn(WorkoutExercise)

    var id: Self { self }

    /// Answered already, here or on the iPhone, so the sheet has nothing left to ask.
    var isAnswered: Bool {
        switch self {
        case .overview: false
        case .feedback(let workoutExercise): !workoutExercise.needsFeedback
        case .checkIn(let workoutExercise): !workoutExercise.checkInPending
        }
    }
}

struct WatchWorkoutView: View {
    private enum AfterDismiss: Equatable {
        case select(Int)
        case overview
        case finish
        case skipWorkout
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchSync.self) private var sync

    let program: Program
    @Bindable var workout: Workout
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition: CGFloat?
    @State private var page: Int
    @State private var sheet: WorkoutSheet?
    @State private var menuExercise: WorkoutExercise?
    @State private var isPresentingMenu = false
    /// Opening another sheet waits until watchOS has dismissed the current one.
    @State private var afterDismiss: AfterDismiss?

    init(program: Program, workout: Workout, onFinished: @escaping () -> Void) {
        self.program = program
        self.workout = workout
        self.onFinished = onFinished
        _page = State(initialValue: workout.currentExerciseIndex)
    }

    private var exercises: [WorkoutExercise] { workout.workoutExercises }

    private var exerciseOnScreen: WorkoutExercise? {
        exercises.indices.contains(page) ? exercises[page] : nil
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, workoutExercise in
                WatchExerciseView(workoutExercise: workoutExercise, onSetLogged: { setLogged(on: workoutExercise) })
                    .background {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let offset = geometry.frame(in: .named("workoutPages")).minX
                            Color.clear.preference(key: WatchPagePosition.self, value: width > 0 && abs(offset) <= width / 2 + 1
                                ? CGFloat(index) - offset / width : nil)
                        }
                    }
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .coordinateSpace(name: "workoutPages")
        .onPreferenceChange(WatchPagePosition.self) { scrollPosition = $0 }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    navigationButton("Back", symbol: "chevron.backward") { dismiss() }
                        .foregroundStyle(.tint)
                    equipmentPill
                        .frame(maxWidth: .infinity)
                }
                .padding(.leading, 2)
                .padding(.trailing, 49)
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .fullScreenCover(item: $menuExercise, onDismiss: menuDismissed) { exercise in
            WatchExerciseMenu(exercise: exercise, workout: workout) { edit, target in
                editExercise(edit, target: target, selected: exercise)
            } onSkipWorkout: {
                afterDismiss = .skipWorkout
                menuExercise = nil
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { presented in
            switch presented {
            case .overview:
                WatchFinishView(
                    workout: workout,
                    selectedExercise: exerciseOnScreen,
                    onSelectExercise: { index in
                        afterDismiss = .select(index)
                        sheet = nil
                    },
                    onSkipWarmups: { exercise in
                        if exercise.nextSet?.isWarmup == true, !exercise.checkInPending {
                            WKInterfaceDevice.current().play(.click)
                            sync.perform { $0.skipWarmups(of: exercise) }
                        }
                        sheet = nil
                    },
                    onFinish: finish
                )
            case .feedback(let workoutExercise):
                WatchFeedbackView(workoutExercise: workoutExercise) { finishedSheet() }
            case .checkIn(let workoutExercise):
                WatchCheckInView(workoutExercise: workoutExercise) { finishedSheet() }
            }
        }
        .onAppear(perform: presentSheetIfNeeded)
        .onChange(of: workout.allExercisesFinished, initial: true) { _, finished in
            if finished, !isPresentingMenu, afterDismiss == nil {
                if sheet == nil {
                    sheet = .overview
                } else if sheet != .overview {
                    afterDismiss = .overview
                }
            }
        }
        .onChange(of: page) { presentSheetIfNeeded() }
        .onChange(of: exerciseOnScreen?.needsFeedback) { presentSheetIfNeeded() }
        .onChange(of: exerciseOnScreen?.checkInPending) { presentSheetIfNeeded() }
        .onChange(of: workout.currentSet?.workoutSet.id) { followSuperset() }
        // The iPhone answered the open sheet first: close it and move on, as if answered here.
        .onChange(of: sheet?.isAnswered == true) { _, isAnswered in
            if isAnswered { finishedSheet() }
        }
        .task(id: workout.currentRest?.endsAt) {
            await RestAlert.schedule(for: workout.currentRest)
        }
        .task {
            // Keeps the app on screen and links it to the iPhone while the workout runs.
            await WorkoutMirroring.shared.begin()
        }
    }

    @ViewBuilder private var equipmentPill: some View {
        if !exercises.isEmpty {
            let position = min(max(0, reduceMotion ? CGFloat(page) : scrollPosition ?? CGFloat(page)), CGFloat(exercises.count - 1))
            let from = Int(position)
            let progress = position - CGFloat(from)
            let sliding = progress > 0.001 && from + 1 < exercises.count
            let rest = exerciseOnScreen.flatMap { workout.rest(shownOn: $0) }
            TimelineView(.periodic(from: rest?.startedAt ?? .now, by: 1)) { context in
                let resting = rest?.isResting(at: context.date) == true
                let seconds = resting ? Int((rest?.remaining(at: context.date) ?? 0).rounded(.up)) : 0
                let remaining = Duration.seconds(seconds)

                Button {
                    guard let exerciseOnScreen else { return }
                    isPresentingMenu = true
                    menuExercise = exerciseOnScreen
                } label: {
                    SwipeWidthLayout(progress: progress) {
                        equipmentLabel(at: Int(position.rounded())).opacity(sliding ? 0 : 1)
                        if sliding {
                            equipmentLabel(at: from)
                            equipmentLabel(at: from + 1)
                        }
                    }
                    .clipShape(.capsule)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .overlay(alignment: .top) {
                        if resting {
                            Label(remaining.formatted(.time(pattern: .minuteSecond)), systemImage: "timer")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .fixedSize()
                                .offset(y: 24)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: resting)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 40)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exerciseOnScreen?.shownExercise?.watchEquipmentName ?? "")
                .accessibilityValue(resting ? "Rest, \(remaining.formatted(.units(allowed: [.minutes, .seconds])))" : "")
                .accessibilityHint("Opens exercise actions")
            }
        }
    }

    private func equipmentLabel(at index: Int) -> some View {
        Text(exercises[index].shownExercise?.watchEquipmentName ?? "")
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 8)
            .frame(height: 21)
    }

    private func navigationButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 25.5, height: 25.5)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func editExercise(_ edit: WatchChange.ExerciseEdit, target: WorkoutExercise, selected: WorkoutExercise) {
        sync.perform { $0.edit(edit, of: target, in: program) }
        if let index = exercises.firstIndex(where: { $0 === selected }) {
            page = index
        }
    }

    private func menuDismissed() {
        isPresentingMenu = false
        if afterDismiss == .skipWorkout {
            sync.perform { $0.skip(workout, in: program) }
            WorkoutMirroring.shared.end()
            Task { await RestAlert.schedule(for: nil) }
            onFinished()
            return
        }
        if afterDismiss == .overview || workout.allExercisesFinished && exerciseOnScreen?.needsFeedback != true {
            afterDismiss = nil
            sheet = .overview
        } else if exerciseOnScreen?.needsFeedback == true {
            presentSheetIfNeeded()
        } else if exerciseOnScreen?.isDone == true {
            advance()
        } else {
            presentSheetIfNeeded()
        }
    }

    private func setLogged(on workoutExercise: WorkoutExercise) {
        save()
        if workoutExercise.needsFeedback {
            sheet = .feedback(workoutExercise)
        } else if workoutExercise.isDone {
            advance()
        }
    }

    /// In a superset, moves to the exercise whose turn it is once a set is logged, here or on the iPhone.
    /// After the round's last exercise that's back to the first, with the rest counting down.
    private func followSuperset() {
        guard
            !isPresentingMenu,
            sheet == nil,
            let exerciseOnScreen,
            let next = workout.currentSet?.workoutExercise,
            exerciseOnScreen.supersetPartners.contains(where: { $0 === next }),
            let index = exercises.firstIndex(where: { $0 === next })
        else { return }
        withAnimation {
            page = index
        }
    }

    /// Feedback or a check-in waits on the exercise on screen, e.g. after relaunching mid-workout.
    private func presentSheetIfNeeded() {
        guard !isPresentingMenu, sheet == nil, afterDismiss == nil, let exerciseOnScreen else { return }
        if exerciseOnScreen.needsFeedback {
            sheet = .feedback(exerciseOnScreen)
        } else if exerciseOnScreen.checkInPending {
            sheet = .checkIn(exerciseOnScreen)
        }
    }

    private func finishedSheet() {
        save()
        sheet = nil
        if afterDismiss != .finish, exerciseOnScreen?.isDone == true {
            afterDismiss = workout.allExercisesFinished ? .overview : .select(workout.currentExerciseIndex)
        }
    }

    private func advance() {
        withAnimation {
            page = workout.currentExerciseIndex
        }
    }

    /// Skips anything still unlogged and asks each partly logged exercise for its feedback, as the
    /// iPhone does, then moves the program on. Finishing a week plans the next one.
    private func finish() {
        afterDismiss = .finish
        sync.perform { $0.skipRemainingSets(of: workout) }
        sheet = nil
    }

    /// Runs as each sheet closes, to ask the next question while Finish Workout is waiting on feedback.
    private func sheetDismissed() {
        switch afterDismiss {
        case .finish:
            askFeedbackOrFinish()
        case .overview:
            afterDismiss = nil
            sheet = .overview
        case .select(let index):
            afterDismiss = nil
            page = index
            presentSheetIfNeeded()
        case .skipWorkout, nil:
            presentSheetIfNeeded()
        }
    }

    /// Asks the next unrated exercise's feedback, and finishes once none is left.
    private func askFeedbackOrFinish() {
        guard workout.status == .active else {
            afterDismiss = nil
            onFinished()
            return
        }
        if let unrated = exercises.first(where: \.needsFeedback) {
            // A sheet still closing comes back here when it's gone.
            if sheet == nil { sheet = .feedback(unrated) }
            return
        }
        afterDismiss = nil
        sync.perform { $0.finish(workout, in: program) }
        WorkoutMirroring.shared.end()
        Task { await RestAlert.schedule(for: nil) }
        onFinished()
    }

    private func save() {
        modelContext.saveTraced("watch workout")
    }
}

private struct WatchPagePosition: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
