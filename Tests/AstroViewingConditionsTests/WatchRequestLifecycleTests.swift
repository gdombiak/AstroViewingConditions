@testable import SharedCode
import XCTest

// MARK: - Manual timeout scheduler (deterministic)

/// Production `WatchRequestTimeoutScheduling` double: records scheduled work and fires on demand.
final class ManualWatchRequestTimeoutScheduler: WatchRequestTimeoutScheduling, @unchecked Sendable {
    final class Handle: WatchRequestTimeoutHandle, @unchecked Sendable {
        private let lock = NSLock()
        private var work: (() -> Void)?
        private(set) var isCancelled = false
        private(set) var didFire = false

        init(work: @escaping @Sendable () -> Void) {
            self.work = work
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            work = nil
            lock.unlock()
        }

        func fire() {
            lock.lock()
            let w = work
            work = nil
            let cancelled = isCancelled
            if !cancelled { didFire = true }
            lock.unlock()
            if !cancelled {
                w?()
            }
        }
    }

    private let lock = NSLock()
    private(set) var handles: [Handle] = []

    func schedule(
        after seconds: TimeInterval,
        work: @escaping @Sendable () -> Void
    ) -> any WatchRequestTimeoutHandle {
        let handle = Handle(work: work)
        lock.lock()
        handles.append(handle)
        lock.unlock()
        return handle
    }

    var lastHandle: Handle? {
        lock.lock(); defer { lock.unlock() }
        return handles.last
    }

    func fireLast() {
        lastHandle?.fire()
    }

    func fireAll() {
        lock.lock()
        let copy = handles
        lock.unlock()
        for h in copy { h.fire() }
    }
}

private enum LifecycleTestError: Error, Equatable {
    case timeout
    case sendFailed
    case decodeFailed
}

// MARK: - Production registry + lifecycle

final class WatchSingleCompletionRegistryTests: XCTestCase {
    func testCompleteRemovesEntryAndResumesOnce() async throws {
        let registry = WatchSingleCompletionRegistry<String>()
        let id = UUID()
        let value = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            registry.store(id, continuation: cont)
            XCTAssertTrue(registry.contains(id))
            XCTAssertEqual(registry.outstandingCount, 1)
            XCTAssertTrue(registry.complete(id, with: .success("ok")))
            XCTAssertFalse(registry.complete(id, with: .success("late")))
            XCTAssertEqual(registry.outstandingCount, 0)
        }
        XCTAssertEqual(value, "ok")
    }

    func testSecondCompleteIsNoOpWithoutDoubleResume() async throws {
        let registry = WatchSingleCompletionRegistry<Int>()
        let id = UUID()
        let value = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            registry.store(id, continuation: cont)
            XCTAssertTrue(registry.complete(id, with: .success(1)))
            // Late timeout / reply
            XCTAssertFalse(registry.complete(id, with: .failure(LifecycleTestError.timeout)))
            XCTAssertFalse(registry.complete(id, with: .success(2)))
        }
        XCTAssertEqual(value, 1)
    }
}

final class WatchRequestLifecycleControllerTests: XCTestCase {
    func testEagerSchedulerTimeoutCompletesOnceWithoutRetainingHandle() async {
        /// Scheduler that runs the timeout callback synchronously inside `schedule`.
        final class EagerTimeoutScheduler: WatchRequestTimeoutScheduling, @unchecked Sendable {
            final class Handle: WatchRequestTimeoutHandle, @unchecked Sendable {
                private(set) var isCancelled = false
                func cancel() { isCancelled = true }
            }
            private(set) var lastHandle: Handle?

            func schedule(
                after seconds: TimeInterval,
                work: @escaping @Sendable () -> Void
            ) -> any WatchRequestTimeoutHandle {
                let handle = Handle()
                lastHandle = handle
                // Synchronous timeout (not production asyncAfter, but allowed by protocol).
                work()
                return handle
            }
        }

        let scheduler = EagerTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: id,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
            }
            XCTFail("expected timeout")
        } catch let error as LifecycleTestError {
            XCTAssertEqual(error, .timeout)
            // After eager timeout: no outstanding request; handle cancelled and not retained.
            XCTAssertEqual(lifecycle.outstandingCount, 0)
            XCTAssertFalse(lifecycle.contains(id))
            XCTAssertTrue(scheduler.lastHandle?.isCancelled == true)
            // Late reply ignored.
            XCTAssertFalse(lifecycle.complete(id, with: .success("late")))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSuccessBeforeTimeoutResumesOnceAndCancelsTimeout() async throws {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        let value = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            lifecycle.begin(
                id: id,
                timeout: 4,
                timeoutError: { LifecycleTestError.timeout },
                continuation: cont
            )
            XCTAssertEqual(lifecycle.outstandingCount, 1)
            XCTAssertTrue(lifecycle.complete(id, with: .success("reply")))
            // Timeout fires later — must not resume again.
            scheduler.fireLast()
            XCTAssertEqual(lifecycle.outstandingCount, 0)
            XCTAssertTrue(scheduler.lastHandle?.isCancelled == true)
        }
        XCTAssertEqual(value, "reply")
    }

    func testTimeoutBeforeLateReplyResumesOnce() async {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: id,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
                scheduler.fireLast()
                // Late reply
                XCTAssertFalse(lifecycle.complete(id, with: .success("late")))
                XCTAssertEqual(lifecycle.outstandingCount, 0)
            }
            XCTFail("expected timeout error")
        } catch let error as LifecycleTestError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSendErrorBeforeTimeoutResumesOnce() async {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: id,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
                XCTAssertTrue(lifecycle.complete(id, with: .failure(LifecycleTestError.sendFailed)))
                scheduler.fireLast()
                XCTAssertFalse(lifecycle.complete(id, with: .success("late")))
            }
            XCTFail("expected send error")
        } catch let error as LifecycleTestError {
            XCTAssertEqual(error, .sendFailed)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testReplyTimeoutRaceExactlyOneWins() async throws {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        // Deterministic race: fire timeout and success back-to-back; only first complete wins.
        let value = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            lifecycle.begin(
                id: id,
                timeout: 4,
                timeoutError: { LifecycleTestError.timeout },
                continuation: cont
            )
            // Interleave both completion attempts without wall-clock sleep.
            let wonReply = lifecycle.complete(id, with: .success("winner"))
            scheduler.fireLast() // would complete with timeout if not already done
            let wonTimeout = lifecycle.complete(id, with: .failure(LifecycleTestError.timeout))
            XCTAssertTrue(wonReply)
            XCTAssertFalse(wonTimeout)
            XCTAssertEqual(lifecycle.outstandingCount, 0)
        }
        XCTAssertEqual(value, "winner")
    }

    func testTimeoutThenReplyRaceTimeoutWins() async {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: id,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
                scheduler.fireLast()
                XCTAssertFalse(lifecycle.complete(id, with: .success("late")))
            }
            XCTFail("expected timeout")
        } catch let error as LifecycleTestError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testMalformedReplyPathCompletesOnceWithDecodeError() async {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let id = UUID()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: id,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
                // Production handleConditionsReply path on missing conditions data:
                XCTAssertTrue(lifecycle.complete(id, with: .failure(LifecycleTestError.decodeFailed)))
                scheduler.fireLast()
                XCTAssertEqual(lifecycle.outstandingCount, 0)
            }
            XCTFail("expected decode error")
        } catch let error as LifecycleTestError {
            XCTAssertEqual(error, .decodeFailed)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testMultipleSimultaneousRequestsAreIsolated() async throws {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<String>(scheduler: scheduler)
        let idA = UUID()
        let idB = UUID()

        let taskA = Task {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: idA,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
            }
        }
        await waitUntil(lifecycle.contains(idA))
        let taskB = Task {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lifecycle.begin(
                    id: idB,
                    timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
            }
        }
        await waitUntil(lifecycle.contains(idB))
        XCTAssertEqual(lifecycle.outstandingCount, 2)

        XCTAssertTrue(lifecycle.complete(idA, with: .success("A")))
        XCTAssertEqual(lifecycle.outstandingCount, 1)
        XCTAssertTrue(lifecycle.contains(idB))
        XCTAssertFalse(lifecycle.contains(idA))

        XCTAssertTrue(lifecycle.complete(idB, with: .success("B")))
        XCTAssertEqual(lifecycle.outstandingCount, 0)

        let a = try await taskA.value
        let b = try await taskB.value
        XCTAssertEqual(a, "A")
        XCTAssertEqual(b, "B")
    }

    func testCompletingADoesNotResumeB() async throws {
        let scheduler = ManualWatchRequestTimeoutScheduler()
        let lifecycle = WatchRequestLifecycleController<Int>(scheduler: scheduler)
        let idA = UUID()
        let idB = UUID()

        let taskA = Task {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
                lifecycle.begin(
                    id: idA, timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
            }
        }
        await waitUntil(lifecycle.contains(idA))
        let taskB = Task {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
                lifecycle.begin(
                    id: idB, timeout: 4,
                    timeoutError: { LifecycleTestError.timeout },
                    continuation: cont
                )
            }
        }
        await waitUntil(lifecycle.contains(idB))
        XCTAssertEqual(lifecycle.outstandingCount, 2)
        XCTAssertTrue(lifecycle.complete(idA, with: .success(1)))
        // A removed; B still outstanding and not resumed.
        XCTAssertFalse(lifecycle.contains(idA))
        XCTAssertTrue(lifecycle.contains(idB))
        XCTAssertEqual(lifecycle.outstandingCount, 1)
        XCTAssertTrue(lifecycle.complete(idB, with: .success(2)))
        let a = try await taskA.value
        let b = try await taskB.value
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 2)
    }

    /// Deterministic wait for registry registration (no wall-clock sleep primary).
    private func waitUntil(
        _ predicate: @autoclosure () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("predicate not satisfied", file: file, line: line)
    }
}

// MARK: - Message builder (CL request correlation encoding)

final class WatchConditionsRequestMessageBuilderTests: XCTestCase {
    func testSavedLocationMessageHasNoCLContext() {
        let id = UUID()
        let message = WatchConditionsRequestMessageBuilder.makeMessage(requestID: id)
        XCTAssertEqual(
            message[WatchConditionsRequestMessageBuilder.typeKey] as? String,
            WatchConditionsRequestMessageBuilder.messageType
        )
        XCTAssertEqual(
            message[WatchConditionsRequestMessageBuilder.idKey] as? String,
            id.uuidString
        )
        XCTAssertNil(message[WatchConditionsRequestMessageBuilder.currentLocationRequestKey])
    }

    func testCurrentLocationMessageEncodesRequestContext() throws {
        let id = UUID()
        let request = WatchCurrentLocationRequestContext(
            requestID: UUID(),
            latitude: 45.5,
            longitude: -122.6
        )
        let message = WatchConditionsRequestMessageBuilder.makeMessage(
            requestID: id,
            currentLocationRequest: request
        )
        let data = try XCTUnwrap(
            message[WatchConditionsRequestMessageBuilder.currentLocationRequestKey] as? Data
        )
        let decoded = try JSONDecoder().decode(WatchCurrentLocationRequestContext.self, from: data)
        XCTAssertEqual(decoded, request)
        XCTAssertTrue(decoded.isStructurallyValid)
    }

    func testRequestIDIsolationAcrossMessages() {
        let a = UUID()
        let b = UUID()
        let msgA = WatchConditionsRequestMessageBuilder.makeMessage(requestID: a)
        let msgB = WatchConditionsRequestMessageBuilder.makeMessage(requestID: b)
        XCTAssertNotEqual(
            msgA[WatchConditionsRequestMessageBuilder.idKey] as? String,
            msgB[WatchConditionsRequestMessageBuilder.idKey] as? String
        )
    }
}
