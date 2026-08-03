import Foundation
import os

/// Process-wide, once-per-process load of the bundled LPATLAS1 provider.
///
/// Initialization performs eager structural validation (~1s class for the production artifact),
/// so loading runs off the main actor. Failure leaves the provider unavailable; scores fall back
/// to night-conditions only (never pristine darkness).
public actor LightPollutionProviderBootstrap {
    public static let shared = LightPollutionProviderBootstrap()

    public enum State: Sendable, Equatable {
        case notStarted
        case loading
        case ready
        case failed
    }

    private var state: State = .notStarted
    private var provider: (any LightPollutionProviding)?
    private var loadTask: Task<(any LightPollutionProviding)?, Never>?
    private let logger = Logger(
        subsystem: "com.astroviewing.conditions",
        category: "LightPollution"
    )

    private init() {}

    /// Current provider if load succeeded; otherwise nil.
    public func currentProvider() -> (any LightPollutionProviding)? {
        provider
    }

    public func currentState() -> State {
        state
    }

    /// Ensure the bundled provider is loaded once. Safe to call repeatedly / concurrently.
    ///
    /// - Parameter preferredBundles: Bundles to search first (e.g. host app bundle in tests).
    ///   URL resolution happens on the caller; heavy init runs off-main.
    @discardableResult
    public func ensureLoaded(preferredBundles: [Bundle] = []) async -> (any LightPollutionProviding)? {
        switch state {
        case .ready:
            return provider
        case .failed:
            return nil
        case .loading:
            if let loadTask {
                return await loadTask.value
            }
            return provider
        case .notStarted:
            state = .loading
            // Resolve URL before detaching (Bundle is not Sendable across isolation).
            let url = BundledLightPollutionResource.resourceURL(in: preferredBundles)
            let task = Task.detached(priority: .userInitiated) { () -> (any LightPollutionProviding)? in
                guard let url else { return nil }
                do {
                    return try BundledLightPollutionResource.loadProvider(
                        from: url,
                        verifyChecksum: false
                    )
                } catch {
                    return nil
                }
            }
            loadTask = task
            let result = await task.value
            if let result {
                provider = result
                state = .ready
                logger.info("LPATLAS1 provider ready")
            } else {
                state = .failed
                logger.error(
                    "LPATLAS1 provider failed to load; observing scores fall back to night conditions"
                )
            }
            loadTask = nil
            return provider
        }
    }

    /// Test support: install a provider without loading the bundle.
    public func installForTesting(_ provider: (any LightPollutionProviding)?) {
        self.provider = provider
        self.state = provider == nil ? .failed : .ready
        self.loadTask = nil
    }

    /// Test support: reset process state between tests.
    public func resetForTesting() {
        loadTask?.cancel()
        loadTask = nil
        provider = nil
        state = .notStarted
    }
}
