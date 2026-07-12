import Foundation
import os

private let firestoreSyncLog = Logger(subsystem: "com.yuedu.app", category: "iCloudSync")

/// Local-only sync stub.
///
/// The original implementation backed account sync (books / sources / replace
/// rules / RSS / reading positions / avatar / profile) on Firebase Firestore +
/// Storage. The project no longer links Firebase, and account sign-in has been
/// removed, so this manager is reduced to a no-op that preserves the public API
/// surface the rest of the app still calls. Wire a real backend here later
/// (your own service) without touching call sites.
@MainActor
final class FirestoreSyncManager: ObservableObject {
    static let shared = FirestoreSyncManager()

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    @Published private(set) var state: SyncState = .idle
    var lastSyncDate: Date?

    /// Master switch for account data sync. Kept OFF: there is no backend wired
    /// after the Firebase integration was removed.
    static let dataSyncEnabled = false

    private let bookStore: BookStore? = nil
    private var isApplyingRemote = false
    private var isSyncing = false

    private init() {}

    var statusTitle: String {
        switch state {
        case .idle: return localized("等待同步")
        case .syncing: return localized("正在同步")
        case .synced: return localized("已同步")
        case .failed: return localized("同步失敗")
        }
    }

    /// No-op: nothing to bind without an account backend.
    func bind(bookStore: BookStore) {}

    /// No-op: local data already lives on device; nothing to adopt from a remote.
    func adoptRestoredLocalData() async {}

    /// No-op: no remote state to reset.
    func resetLocalSyncState() {
        state = .idle
        lastSyncDate = nil
    }

    /// No-op: profile sync is disabled without an account backend.
    func upsertCurrentProfile(provider: String? = nil) async throws {}

    /// No-op: avatar upload is disabled without an account backend.
    func uploadAvatar(data: Data) async throws -> URL {
        throw NSError(
            domain: "FirestoreSyncManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: localized("尚未登入，無法上傳頭像")]
        )
    }

    /// No-op: reading-position pushes are disabled without an account backend.
    /// Local position persistence is handled by `JSONFileReadingPositionStore`.
    func scheduleReadingPositionPush(_ position: CoreTextReadingPosition, for bookId: String) {}
}
