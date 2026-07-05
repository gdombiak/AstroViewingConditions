import Foundation

public struct TimeoutError: Error, Sendable, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String = "The request timed out. Please try again.") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum AsyncTimeout {
    public static func run<T: Sendable>(
        seconds: TimeInterval,
        error: any Error & Sendable = TimeoutError(),
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = TimeoutRace<T>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                race.setOperation(Task {
                    do { race.resolve(.success(try await operation())) }
                    catch { race.resolve(.failure(error)) }
                })
                race.setTimer(Task {
                    do {
                        try await Task.sleep(for: .seconds(seconds))
                        race.resolve(.failure(error))
                    } catch { }
                })
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }
}

private final class TimeoutRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var result: Result<Value, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func setOperation(_ task: Task<Void, Never>) { set(task, operation: true) }
    func setTimer(_ task: Task<Void, Never>) { set(task, operation: false) }

    private func set(_ task: Task<Void, Never>, operation: Bool) {
        lock.lock()
        if finished {
            lock.unlock()
            task.cancel()
            return
        }
        if operation { operationTask = task } else { timerTask = task }
        lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let operationTask = self.operationTask
        let timerTask = self.timerTask
        lock.unlock()

        operationTask?.cancel()
        timerTask?.cancel()
        continuation?.resume(with: result)
    }
}
