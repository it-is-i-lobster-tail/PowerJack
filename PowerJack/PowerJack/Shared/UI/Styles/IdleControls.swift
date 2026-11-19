//
//  IdleControls.swift
//  PowerJack
//
//  Fades a workout's controls away after a few idle seconds, so the sets have the screen.
//

import SwiftUI
import UIKit

/// Fades the bottom bar, the exercise strip and the top buttons while a workout sits idle.
/// The workout turns it on while it shows. A tap anywhere or a new exercise brings the
/// controls back, except a tap that edits or checks off a set.
@Observable
final class IdleControls {
    static let idleDelay = Duration.seconds(3)
    static let fade = Animation.easeInOut(duration: 0.4)
    /// A set tap and the window's tap land together, in either order.
    private static let tapWindow = Duration.milliseconds(300)

    /// True while the controls are faded out.
    private(set) var isHidden = false

    @ObservationIgnored private var isOn = false
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var lastSetTap = ContinuousClock.now - .seconds(1)

    /// Starts the idle wait. The controls show until it runs out.
    func turnOn() {
        isOn = true
        show()
    }

    /// Shows the controls for good, e.g. when the workout closes.
    func turnOff() {
        isOn = false
        revealTask?.cancel()
        hideTask?.cancel()
        setHidden(false)
    }

    /// Brings the controls back and starts the idle wait again.
    func show() {
        setHidden(false)
        restartIdleWait()
    }

    /// Holds the controls as they are, e.g. while a weight or reps field is being typed in.
    func pause(_ paused: Bool) {
        isPaused = paused
        restartIdleWait()
    }

    /// A tap on a set's field or check circle, which leaves the controls as they are.
    func noteSetTap() {
        lastSetTap = .now
        revealTask?.cancel()
    }

    /// Any tap in the window. Waits a moment to learn whether it was a set tap.
    fileprivate func noteWindowTap() {
        guard isOn, ContinuousClock.now - lastSetTap > Self.tapWindow else { return }
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    private func restartIdleWait() {
        hideTask?.cancel()
        guard isOn, !isPaused else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            self?.setHidden(true)
        }
    }

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        withAnimation(Self.fade) { isHidden = hidden }
    }
}

extension View {
    /// Fades this control out while `controls` are idle, and lets taps pass through it.
    func fadesWhenIdle(_ controls: IdleControls?) -> some View {
        let isHidden = controls?.isHidden == true
        return opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
            .accessibilityHidden(isHidden)
    }

    /// Tells `controls` about every tap in the window, including ones on the navigation bar.
    /// Apply once at the root.
    func revealsIdleControlsOnTap(_ controls: IdleControls) -> some View {
        background(WindowTapObserver(controls: controls))
    }
}

/// A window-wide tap recognizer that watches taps without blocking them.
private struct WindowTapObserver: UIViewRepresentable {
    let controls: IdleControls

    func makeUIView(context: Context) -> InstallerView { InstallerView(controls: controls) }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private let controls: IdleControls

        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(controls: IdleControls) {
            self.controls = controls
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func handleTap() {
            controls.noteWindowTap()
        }

        // A tap in a text field is typing, not a call for the controls.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
