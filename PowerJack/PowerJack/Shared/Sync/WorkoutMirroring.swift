//
//  WorkoutMirroring.swift
//  PowerJack
//
//  While a workout is open on the watch, it runs a strength training session that HealthKit
//  mirrors to the iPhone. That keeps the watch app on screen and gives both devices a fast,
//  direct channel without polling: the watch sends its changes, the iPhone answers with its
//  program. Nothing is saved to Health. Without Health permission, `DeviceLink` does the job.
//

import Foundation
import HealthKit
import OSLog

@MainActor
final class WorkoutMirroring: NSObject {
    static let shared = WorkoutMirroring()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    #if os(watchOS)
    private static let askedForHealthKey = "sync.askedForHealth"

    /// Takes the program the iPhone sent back. Set by `WatchSync`.
    var onData: ((Data) -> Void)?

    /// Whether the session runs and reaches the iPhone.
    private(set) var isMirroring = false

    /// Starts the session for the workout on screen, or picks up the one running before the app relaunched.
    func begin() async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        do {
            if let recovered = try await healthStore.recoverActiveWorkoutSession() {
                adopt(recovered)
                return
            }
            // Asked once, as the first workout opens. Without permission the link works on its own.
            if !UserDefaults.standard.bool(forKey: Self.askedForHealthKey) {
                UserDefaults.standard.set(true, forKey: Self.askedForHealthKey)
                try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            }
            guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            adopt(session)
            session.startActivity(with: .now)
            try await session.startMirroringToCompanionDevice()
            isMirroring = true
        } catch {
            // Health permission declined, or no iPhone to mirror to: the link still works without it.
            Logger.sync.info("Workout session not mirrored: \(error.localizedDescription)")
        }
    }

    /// Ends the session once the workout is finished.
    func end() {
        session?.end()
        session = nil
        isMirroring = false
    }

    private func adopt(_ session: HKWorkoutSession) {
        session.delegate = self
        self.session = session
        isMirroring = session.state == .running
    }
    #else
    /// Applies the watch's changes and answers with the program. Set by `PhoneSync`.
    var onData: ((Data) -> Data?)?

    /// The system starts the iPhone app in the background when the watch mirrors a session to it,
    /// so this is set as the app launches.
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in WorkoutMirroring.shared.adopt(session) }
        }
    }

    private func adopt(_ session: HKWorkoutSession) {
        session.delegate = self
        self.session = session
    }
    #endif

    /// Sends `data` over the mirrored session. Returns false when there's none, so the caller uses `DeviceLink`.
    func send(_ data: Data) async -> Bool {
        guard let session else { return false }
        do {
            try await session.sendToRemoteWorkoutSession(data: data)
            return true
        } catch {
            Logger.sync.debug("Could not send over the workout session: \(error.localizedDescription)")
            return false
        }
    }

    private func received(_ data: Data) async {
        #if os(watchOS)
        onData?(data)
        #else
        if let answer = onData?(data) {
            _ = await send(answer)
        }
        #endif
    }

    private func ended(_ ended: HKWorkoutSession) {
        guard ended === session else { return }
        session = nil
        #if os(watchOS)
        isMirroring = false
        #endif
    }
}

extension WorkoutMirroring: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.ended(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let failure = error.localizedDescription
        Task { @MainActor in Logger.sync.error("Workout session failed: \(failure)") }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for item in data {
                await self.received(item)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in
            #if os(watchOS)
            self.isMirroring = false
            #else
            self.ended(workoutSession)
            #endif
        }
    }
}
