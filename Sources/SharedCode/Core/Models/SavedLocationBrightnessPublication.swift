import Foundation

/// Process-local monotonic ordering for authoritative saved-location brightness snapshots.
///
/// Revisions are **not** persisted in `savedLocationModeledBrightness.json`. They only
/// order in-process publication relative to unstructured provider-fetch tasks.
enum SavedLocationBrightnessPublicationOrder: Sendable {
    /// Lock-protected counter; `@unchecked Sendable` because all access is serialized by `lock`.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var nextValue: UInt64 = 1

        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            let value = nextValue
            nextValue &+= 1
            return value
        }

        func reset(startingAt start: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            nextValue = start
        }
    }

    private static let counter = Counter()

    /// Synchronously allocates the next publication revision (strictly increasing).
    static func next() -> UInt64 {
        counter.next()
    }

    /// Test-only: reset the process-local counter.
    static func resetForTesting(startingAt start: UInt64 = 1) {
        counter.reset(startingAt: start)
    }
}

/// An authoritative full-list snapshot of saved locations for brightness metadata sync,
/// stamped with a process-local publication revision.
public struct SavedLocationBrightnessPublication: Sendable, Equatable {
    /// Process-local publication order (higher = later authoritative snapshot).
    public let revision: UInt64
    public let locations: [SavedLocationBrightnessAnchor]

    /// Creates a production publication, allocating the next process-local revision
    /// **synchronously** at the call site (before any `await` / unstructured `Task`).
    public static func makeAuthoritative(
        locations: [SavedLocationBrightnessAnchor]
    ) -> SavedLocationBrightnessPublication {
        SavedLocationBrightnessPublication(
            revision: SavedLocationBrightnessPublicationOrder.next(),
            locations: locations
        )
    }

    /// Test-only: explicit revision without touching the global counter.
    static func makeForTesting(
        revision: UInt64,
        locations: [SavedLocationBrightnessAnchor]
    ) -> SavedLocationBrightnessPublication {
        SavedLocationBrightnessPublication(revision: revision, locations: locations)
    }
}
