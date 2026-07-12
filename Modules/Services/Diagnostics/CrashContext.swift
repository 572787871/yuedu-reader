import Foundation
import os

/// Lightweight, process-local diagnostics sink. It keeps the same breadcrumb /
/// context-key / non-fatal surface the rest of the app calls, but persists nothing
/// to a remote crash reporter — the project no longer links Crashlytics. All calls
/// are safe to make from any actor/queue.
enum CrashContext {
    private static let log = Logger(subsystem: "com.yuedu.app", category: "CrashContext")

    /// A timestamped breadcrumb that shows up in the next crash/non-fatal report's
    /// log tab. Use for user actions and subsystem milestones.
    static func breadcrumb(_ message: String) {
        log.debug("🍞 \(message, privacy: .public)")
        log.debug("🍞 \(message, privacy: .public)")
    }

    /// A persistent key/value attached to every subsequent report (overwrites the
    /// previous value for the same key). Use for "current state" (open book,
    /// reader mode, syncing…).
    static func setKey(_ key: String, _ value: String) {
        log.debug("🔑 \(key, privacy: .public) = \(String(describing: value), privacy: .public)")
    }

    static func setKey(_ key: String, _ value: Int) {
        log.debug("🔑 \(key, privacy: .public) = \(String(describing: value), privacy: .public)")
    }

    static func setKey(_ key: String, _ value: Bool) {
        log.debug("🔑 \(key, privacy: .public) = \(String(describing: value), privacy: .public)")
    }

    /// Record a non-fatal error so it surfaces in Crashlytics without crashing the
    /// app. `extra` becomes additional info on the report.
    static func recordNonFatal(
        domain: String,
        code: Int = 0,
        message: String,
        extra: [String: String] = [:]
    ) {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        for (key, value) in extra { info[key] = value }
        log.error("⚠️ non-fatal [\(domain, privacy: .public)] \(message, privacy: .public)")
        log.error("⚠️ non-fatal [\(domain, privacy: .public)] \(message, privacy: .public)")
    }
}
