import Foundation

/// Mirroring record used by the iCloud (CloudKit) sync path. Kept separate
/// from `FirestoreSyncManager` so `ICloudSyncManager` and the merge tests
/// compile regardless of whether a remote account backend is wired in.
struct FirestoreSyncRecord<Value> {
    var id: String
    var value: Value?
    var updatedAt: Date
    var deleted: Bool
}

struct SyncShadowEntry: Codable, Equatable {
    var updatedAt: Date
    var hash: String
    var deleted: Bool
}

/// Last-write-wins merge that understands tombstones in both directions.
/// Shared by the CloudKit sync path; the original Firebase-backed implementation
/// reused the same algorithm. Decoupled here so it survives the account-backend
/// removal.
enum FirestoreSyncMerge {
    static func merge<Value>(
        local: [Value],
        remote: [FirestoreSyncRecord<Value>],
        shadow: [String: SyncShadowEntry],
        id: (Value) -> String,
        hash: (Value) -> String,
        fallbackUpdatedAt: (Value) -> Date
    ) -> (values: [Value], shadow: [String: SyncShadowEntry]) {
        var orderedIDs: [String] = []
        var valuesByID: [String: Value] = [:]
        var newShadow: [String: SyncShadowEntry] = [:]

        for (sid, entry) in shadow where entry.deleted {
            newShadow[sid] = entry
        }

        for value in local {
            let valueID = id(value)
            orderedIDs.append(valueID)
            valuesByID[valueID] = value
            let updatedAt = shadow[valueID]?.updatedAt ?? fallbackUpdatedAt(value)
            newShadow[valueID] = SyncShadowEntry(updatedAt: updatedAt, hash: hash(value), deleted: false)
        }

        for record in remote {
            let localEntry = newShadow[record.id]

            if record.deleted {
                if let localEntry, !localEntry.deleted, localEntry.updatedAt > record.updatedAt {
                    continue
                }
                valuesByID[record.id] = nil
                newShadow[record.id] = SyncShadowEntry(updatedAt: record.updatedAt, hash: "", deleted: true)
                continue
            }

            guard let value = record.value else { continue }

            if let localEntry {
                if record.updatedAt >= localEntry.updatedAt {
                    if localEntry.deleted {
                        orderedIDs.append(record.id)
                    }
                    valuesByID[record.id] = value
                    newShadow[record.id] = SyncShadowEntry(updatedAt: record.updatedAt, hash: hash(value), deleted: false)
                }
            } else {
                orderedIDs.append(record.id)
                valuesByID[record.id] = value
                newShadow[record.id] = SyncShadowEntry(updatedAt: record.updatedAt, hash: hash(value), deleted: false)
            }
        }

        let values = orderedIDs.compactMap { valuesByID[$0] }
        return (values, newShadow)
    }
}

/// Per-collection tombstone/shadow cache persisted in `UserDefaults`.
enum SyncShadowStore {
    private static let prefix = "yd_firestore_shadow_"

    static func load(_ collection: String) -> [String: SyncShadowEntry] {
        guard let data = UserDefaults.standard.data(forKey: prefix + collection),
              let decoded = try? JSONDecoder().decode([String: SyncShadowEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func save(_ collection: String, _ entries: [String: SyncShadowEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: prefix + collection)
    }

    static func clearAll(collections: [String]) {
        for collection in collections {
            UserDefaults.standard.removeObject(forKey: prefix + collection)
        }
    }
}
