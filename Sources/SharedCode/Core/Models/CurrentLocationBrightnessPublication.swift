import Foundation

/// Process-local monotonic ordering for authoritative Current Location brightness snapshots.
///
/// Separate stream from `SavedLocationBrightnessPublicationOrder`. Revisions are **not**
/// persisted in `currentLocationModeledBrightness.json`.
enum CurrentLocationBrightnessPublicationOrder: Sendable {
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

    static func next() -> UInt64 {
        counter.next()
    }

    static func resetForTesting(startingAt start: UInt64 = 1) {
        counter.reset(startingAt: start)
    }
}

/// Versioned authoritative Current Location coordinate snapshot for brightness metadata sync.
public struct CurrentLocationBrightnessPublication: Sendable, Equatable {
    public let revision: UInt64
    public let anchor: CurrentLocationBrightnessAnchor

    /// Allocates the next process-local revision **synchronously** (before any `await` / Task).
    public static func makeAuthoritative(
        anchor: CurrentLocationBrightnessAnchor
    ) -> CurrentLocationBrightnessPublication {
        CurrentLocationBrightnessPublication(
            revision: CurrentLocationBrightnessPublicationOrder.next(),
            anchor: anchor
        )
    }

    static func makeForTesting(
        revision: UInt64,
        anchor: CurrentLocationBrightnessAnchor
    ) -> CurrentLocationBrightnessPublication {
        CurrentLocationBrightnessPublication(revision: revision, anchor: anchor)
    }
}
