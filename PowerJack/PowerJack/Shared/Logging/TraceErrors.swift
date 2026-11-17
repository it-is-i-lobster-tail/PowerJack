//
//  TraceErrors.swift
//  PowerJack
//
//  What went wrong, in a form safe for the trace: an error's kind, domain and codes, and for a
//  decoding error the keys it stopped at. Never an error's text or a value, which can hold names.
//

import CloudKit
import Foundation
import OSLog
import SwiftData

extension TraceLog {
    /// e.g. "NSCocoaErrorDomain 134060, underlying NSSQLiteErrorDomain 13" or
    /// "DecodingError.keyNotFound reps at weeks.0.workouts.2".
    nonisolated static func describe(_ error: any Error) -> String {
        if let decodingError = error as? DecodingError {
            return describe(decodingError)
        }
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += ", underlying \(underlying.domain) \(underlying.code)"
        }
        // The codes only: the keys are record names.
        if let cloudKitError = error as? CKError, cloudKitError.code == .partialFailure,
           let partialErrors = cloudKitError.partialErrorsByItemID {
            let codes = Set(partialErrors.values.map { ($0 as NSError).code }).sorted()
            text += ", partial failures \(codes.map(String.init).joined(separator: " "))"
        }
        return text
    }

    private nonisolated static func describe(_ error: DecodingError) -> String {
        let (kind, context): (String, DecodingError.Context?) = switch error {
        case .typeMismatch(_, let context): ("typeMismatch", context)
        case .valueNotFound(_, let context): ("valueNotFound", context)
        case .keyNotFound(let key, let context): ("keyNotFound \(key.stringValue)", context)
        case .dataCorrupted(let context): ("dataCorrupted", context)
        @unknown default: ("unknown", nil)
        }
        let path = (context?.codingPath ?? []).map { $0.intValue.map(String.init) ?? $0.stringValue }
        return "DecodingError.\(kind)" + (path.isEmpty ? "" : " at \(path.joined(separator: "."))")
    }
}

extension ModelContext {
    /// Saves, and records a failure in the log and on the trace instead of dropping it. `reason`
    /// says what was saved, e.g. "set logged".
    func saveTraced(_ reason: String) {
        do {
            try save()
        } catch {
            Logger.persistence.error("Could not save (\(reason, privacy: .public)): \(error.localizedDescription)")
            TraceLog.record(.data, "Save failed (\(reason)): \(TraceLog.describe(error))")
        }
    }
}
