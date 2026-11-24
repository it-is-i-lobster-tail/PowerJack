//
//  WatchExerciseView.swift
//  PowerJackWatch
//
//  Log the next set as shown, or tap a value to adjust it with the Digital Crown.
//

import SwiftData
import SwiftUI
import WatchKit

struct WatchExerciseView: View {
    @Environment(WatchSync.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Bindable var workoutExercise: WorkoutExercise
    let onSetLogged: () -> Void

    @State private var entry: SetEntry?
    @State private var editing: SetField?
    @State private var weightAlert = 0
    @State private var repsAlert = 0

    private var exercise: Exercise? { workoutExercise.shownExercise }
    private var repsOnly: Bool { exercise?.repsOnly ?? false }
    private var workoutSet: WorkoutSet? { workoutExercise.nextSet }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        exerciseHeading

                        if workoutExercise.checkInPending {
                            Label("Check-in required", systemImage: "cross.case")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else if let workoutSet, let entry {
                            setHeader(workoutSet)
                            Spacer(minLength: 4)
                            values(entry)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer(minLength: 4)
                        } else {
                            Label(workoutExercise.workingSetsDoneText, systemImage: workoutExercise.status == .skipped ? "forward.circle" : "checkmark.circle")
                                .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                }
                .scrollEdgeEffectHidden(true, for: .top)
            }
            .padding(.top, 6)
            if !workoutExercise.checkInPending, let workoutSet, let entry {
                primaryAction(entry, on: workoutSet)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationDestination(item: $editing) { field in
            if let workoutSet, let entry = Binding($entry) {
                SetValueEditor(field: field, entry: dial(entry, on: workoutSet))
            }
        }
        .onChange(of: workoutSet?.id, initial: true) {
            editing = nil
            entry = workoutSet.map { SetEntry(for: $0) }
        }
        .onChange(of: workoutExercise.checkInPending) {
            if workoutExercise.checkInPending { editing = nil }
        }
        .onChange(of: shownValues) { followSet() }
    }

    @ScaledMetric(relativeTo: .subheadline) private var headingSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var supersetLabelSize: CGFloat = 10

    private var exerciseHeading: some View {
        Text(movementName)
            .font(.system(size: headingSize, weight: .semibold))
            .lineLimit(1, reservesSpace: true)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var movementName: String {
        guard let exercise else { return "Exercise" }
        let equipment = NSRegularExpression.escapedPattern(for: exercise.watchEquipmentName)
        let name = exercise.exerciseName
            .replacingOccurrences(of: #"(?i)\b"# + equipment + #"\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—,: "))
        return name.isEmpty ? "Exercise" : name
    }

    private func setHeader(_ workoutSet: WorkoutSet) -> some View {
        let counter = setCounter(workoutSet)
        return Group {
            if let index = workoutExercise.supersetIndex {
                let superset = HStack(spacing: 3) {
                    Image(systemName: "link")
                        .accessibilityHidden(true)
                    Text("Superset \(Workout.supersetLetter(at: index))")
                }
                .font(.system(size: supersetLabelSize))
                .foregroundStyle(SupersetStyle.color(at: index))
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        counter
                        superset
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        counter
                        Spacer(minLength: 0)
                        superset
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
            } else {
                counter
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func setCounter(_ workoutSet: WorkoutSet) -> some View {
        let number = workoutExercise.number(of: workoutSet)
        let count = workoutExercise.count(sameTypeAs: workoutSet)
        return HStack(spacing: 3) {
            phaseLabel(isWarmup: workoutSet.isWarmup)
            Text("\(number)/\(count)")
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(number)))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: workoutSet.id)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(workoutSet.isWarmup ? "Warmup" : "Working") \(number) of \(count)")
    }

    private func phaseLabel(isWarmup: Bool) -> some View {
        let current = isWarmup ? "Warmup:" : "Working:"
        let previous = isWarmup ? "Working:" : "Warmup:"
        let incoming = Array(current)
        let outgoing = Array(previous)
        let stagger = 0.055
        let hop = 0.22
        let tail = 0.46
        let count = max(incoming.count, outgoing.count)
        let duration = Double(count - 1) * stagger + hop + tail
        return Text("Working:")
            .hidden()
            .overlay(alignment: .leading) {
                Color.clear.keyframeAnimator(initialValue: duration, trigger: isWarmup) { _, elapsed in
                    HStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            let age = elapsed - Double(index) * stagger
                            let phase = min(1, max(0, age / hop))
                            let lift = pow(sin(.pi * phase), 2)
                            let letters = age < hop / 2 && !reduceMotion ? outgoing : incoming
                            let tint = max(0, 1 - max(0, age - hop / 2) / (hop / 2 + tail))
                            let intensity = min(1, max(0, age / (hop / 2))) * tint * tint
                            if letters.indices.contains(index) {
                                Text(String(letters[index]))
                                    .overlay { Text(String(letters[index])).foregroundStyle(.cyan).opacity(intensity) }
                                    .offset(y: reduceMotion ? 0 : -3 * lift)
                            }
                        }
                    }
                    .fixedSize()
                } keyframes: { _ in
                    MoveKeyframe(0)
                    LinearKeyframe(duration, duration: duration)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current)
    }

    @ViewBuilder private func values(_ entry: SetEntry) -> some View {
        if repsOnly {
            valueButton(.reps, entry: entry)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    valueButton(.weight, entry: entry)
                    Image(systemName: "multiply")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 32)
                        .accessibilityHidden(true)
                    valueButton(.reps, entry: entry)
                }
                VStack(alignment: .leading, spacing: 4) {
                    valueButton(.weight, entry: entry)
                    valueButton(.reps, entry: entry)
                }
            }
        }
    }

    private func valueButton(_ field: SetField, entry: SetEntry) -> some View {
        Button {
            editing = field
        } label: {
            Text(field.value(in: entry))
                .font(.headline)
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 32)
                .glassEffect(.regular.interactive(), in: .capsule)
                .keyframeAnimator(initialValue: FieldMotion(), trigger: field == .weight ? weightAlert : repsAlert) { capsule, motion in
                    capsule
                        .scaleEffect(reduceMotion ? 1 : motion.scale)
                        .offset(x: reduceMotion ? 0 : motion.offset)
                        .brightness(reduceMotion ? motion.scale - 1 : 0)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1.15, duration: 0.09, timingCurve: .easeInOut)
                        LinearKeyframe(1.15, duration: 0.10)
                        LinearKeyframe(1, duration: 0.13, timingCurve: .easeInOut)
                    }
                    KeyframeTrack(\.offset) {
                        LinearKeyframe(-3, duration: 0.045)
                        LinearKeyframe(3, duration: 0.075)
                        LinearKeyframe(-2, duration: 0.065)
                        SpringKeyframe(0, duration: 0.16, spring: .bouncy(duration: 0.16, extraBounce: 0.08))
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(field.title)
        .accessibilityValue(field.value(in: entry))
        .accessibilityHint("Opens the Digital Crown editor")
    }

    private func primaryAction(_ entry: SetEntry, on set: WorkoutSet) -> some View {
        let needsWeight = !repsOnly && entry.weightTenthsPounds == nil
        let needsReps = entry.reps.map(WorkoutSet.isValidReps) != true
        let incomplete = needsWeight || needsReps
        let missingHint = needsWeight && needsReps ? "Enter weight and reps" : (needsWeight ? "Enter weight" : "Enter reps")
        return Button {
            guard workoutSet === set else { return }
            if incomplete {
                if needsWeight { weightAlert += 1 }
                if needsReps { repsAlert += 1 }
                WKInterfaceDevice.current().play(.failure)
                AccessibilityNotification.Announcement(missingHint).post()
            } else {
                sync.perform { $0.log(entry, on: set, of: workoutExercise) }
                WKInterfaceDevice.current().play(.success)
                onSetLogged()
            }
        } label: {
            Text("Log Set")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.green)
        .opacity(incomplete ? 0.45 : 1)
        .accessibilityLabel("Log \(workoutExercise.setText(for: set))")
        .accessibilityHint(incomplete ? missingHint : "")
    }

    /// What the next set shows: what's entered, else its target.
    private var shownValues: [Int?] {
        [workoutSet?.upcomingWeightTenthsPounds, workoutSet?.upcomingReps]
    }

    private func followSet() {
        guard let workoutSet, let entry, !entry.matches(workoutSet, repsOnly: repsOnly) else { return }
        self.entry = SetEntry(for: workoutSet)
    }

    /// Each edit is entered live. Ignore callbacks from an editor whose set changed on iPhone.
    private func dial(_ entry: Binding<SetEntry>, on set: WorkoutSet) -> Binding<SetEntry> {
        Binding {
            entry.wrappedValue
        } set: { newValue in
            guard workoutSet === set, newValue != entry.wrappedValue else { return }
            entry.wrappedValue = newValue
            sync.performSoon { $0.enter(newValue, on: set, of: workoutExercise) }
        }
    }
}

private struct FieldMotion {
    var scale: CGFloat = 1
    var offset: CGFloat = 0
}

private enum SetField: Hashable {
    case weight, reps

    var title: LocalizedStringKey {
        self == .weight ? "Weight" : "Reps"
    }

    func value(in entry: SetEntry) -> String {
        switch self {
        case .weight: entry.isBodyweight ? "BW" : "\(entry.weightText) \(entry.unit.symbol)"
        case .reps: "\(entry.reps.map(String.init) ?? "—") reps"
        }
    }
}

private struct SetValueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var crownFocused: Bool

    let field: SetField
    @Binding var entry: SetEntry

    private var steps: Binding<Double> {
        switch field {
        case .weight: $entry.weightSteps
        case .reps: Binding(get: { Double(entry.reps ?? 0) }, set: { value in
            let reps = Int(value.rounded())
            if WorkoutSet.isValidReps(reps) { entry.reps = reps }
        })
        }
    }

    private var bounds: ClosedRange<Double> {
        if field == .reps { return (entry.reps == nil ? 0 : 1)...Double(WorkoutSet.maxReps) }
        // Zero is valid for added bodyweight. For other equipment it means "no entry"
        // and cannot replace a previously entered weight on the paired phone.
        let minimum = min(entry.addsToBodyweight ? 0 : 1, entry.weightSteps)
        return minimum...entry.maxWeightSteps
    }

    var body: some View {
        VStack(spacing: 2) {
            ViewThatFits(in: .vertical) {
                controls
                ScrollView { controls }
            }
            .frame(maxHeight: .infinity)

            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(field.title)
        .onAppear { crownFocused = true }
    }

    private var controls: some View {
        VStack(spacing: 2) {
            Text(field.value(in: entry))
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(steps, from: bounds.lowerBound, through: bounds.upperBound, by: 1,
                                      sensitivity: field == .weight ? .medium : .low, isContinuous: false,
                                      isHapticFeedbackEnabled: true)
                .accessibilityLabel(field.title)
                .accessibilityValue(field.value(in: entry))
                .accessibilityHint("Turn the Digital Crown to adjust")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(by: 1)
                    case .decrement: adjust(by: -1)
                    @unknown default: break
                    }
                }

            GlassEffectContainer {
                HStack {
                    adjustmentButton(increasing: false)
                    Text("Turn Crown")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                    adjustmentButton(increasing: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func adjustmentButton(increasing: Bool) -> some View {
        Button {
            adjust(by: increasing ? 1 : -1)
            crownFocused = true
        } label: {
            Image(systemName: increasing ? "plus" : "minus")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .frame(width: 44, height: 44)
        .disabled(increasing ? steps.wrappedValue >= bounds.upperBound : steps.wrappedValue <= bounds.lowerBound)
        .accessibilityLabel(increasing ? "Increase" : "Decrease")
    }

    private func adjust(by change: Double) {
        steps.wrappedValue = min(bounds.upperBound, max(bounds.lowerBound, steps.wrappedValue + change))
    }
}

extension Exercise {
    var watchEquipmentName: String {
        // "Leg Press" names both the movement and its dedicated machine.
        if equipment == .legPress, exerciseName.caseInsensitiveCompare(equipment.displayName) == .orderedSame {
            return Equipment.machine.displayName
        }
        return equipment.displayName
    }
}
