import Foundation
import WatchConnectivity
import SharedCode

private final class WatchReplyHandler: @unchecked Sendable {
    private let replyHandler: ([String: Any]) -> Void
    
    init(_ replyHandler: @escaping ([String: Any]) -> Void) {
        self.replyHandler = replyHandler
    }
    
    func reply(_ message: [String: Any]) {
        replyHandler(message)
    }
}

struct WatchConditionsRequestAcquirer: Sendable {
    private let conditionsRepository: SharedConditionsRepository

    init(conditionsRepository: SharedConditionsRepository = SharedConditionsRepository()) {
        self.conditionsRepository = conditionsRepository
    }

    /// Performs the normal shared acquisition first, then falls back only to
    /// a cached payload that is proven to match the requested location.
    func conditions(
        for location: CachedLocation?,
        apiKey: String,
        referenceDate: Date = Date()
    ) async -> ViewingConditions? {
        guard let location else {
            return nil
        }

        do {
            return try await conditionsRepository.conditions(
                for: location,
                apiKey: apiKey,
                referenceDate: referenceDate
            ).conditions
        } catch {
            return await conditionsRepository.matchingCachedConditions(for: location)
        }
    }
}

enum WatchConditionsRequestLocationResolver {
    static func resolve(
        selectedLocation: SelectedLocation?,
        savedLocations: [CachedLocation],
        cachedConditions: ViewingConditions?
    ) -> CachedLocation? {
        if let selectedLocation,
           selectedLocation.source == .saved,
           let selectedID = selectedLocation.id,
           let savedLocation = savedLocations.first(where: { $0.id == selectedID }) {
            return savedLocation
        }

        if let selectedLocation,
           selectedLocation.latitude != 0,
           selectedLocation.longitude != 0 {
            return CachedLocation(
                id: selectedLocation.source == .saved ? selectedLocation.id : nil,
                name: selectedLocation.name,
                latitude: selectedLocation.latitude,
                longitude: selectedLocation.longitude
            )
        }

        return cachedConditions?.location
    }
}

@MainActor
public class WatchConnectivityService: NSObject, ObservableObject {
    public static let shared = WatchConnectivityService()
    
    @Published public var isReachable = false
    @Published public var isPaired = false
    
    private var session: WCSession?
    private let conditionsRepository = SharedConditionsRepository()
    /// Last-known companion pieces so each `updateApplicationContext` is a complete snapshot.
    private var snapshotAccumulator = WatchCompanionSnapshotAccumulator()
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        seedSnapshotAccumulator()
    }

    private func seedSnapshotAccumulator() {
        let selected = LocationStorageService.shared.loadSelectedLocation()
        let locations = LocationStorageService.shared.loadSavedLocations()
        let unitSystem = UnitSystemStorage.loadSelectedUnitSystem()
        let samples = WatchLocationsBrightnessPriming.validSamples(for: locations)
        let sessionSnapshot = session.flatMap {
            WatchCompanionSnapshotCodec.decodeAny($0.applicationContext)
        }
        let restored = WatchCompanionSnapshotReseed.restoredConditions(
            selectedLocation: selected,
            sessionSnapshot: sessionSnapshot,
            repositoryConditions: AppGroupStorage.loadConditions(),
            rebuildObservingQuality: { conditions, selectedLocation in
                WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
                    conditions: conditions,
                    selectedLocation: selectedLocation
                )
            }
        )
        snapshotAccumulator = WatchCompanionSnapshotAccumulator(
            selectedLocation: selected,
            locations: locations,
            conditions: restored?.conditions,
            observingQuality: restored?.observingQuality,
            unitSystem: unitSystem,
            modeledBrightnessSamples: samples
        )
    }
    
    public func sendLocationsToWatch(_ locations: [CachedLocation]) {
        let samples = WatchLocationsBrightnessPriming.validSamples(for: locations)
        snapshotAccumulator.setLocations(locations, brightnessSamples: samples)
        if snapshotAccumulator.selectedLocation == nil {
            snapshotAccumulator.selectedLocation = LocationStorageService.shared.loadSelectedLocation()
        }
        publishCompanionSnapshot()
    }
    
    public func sendCurrentLocationToWatch(_ location: CachedLocation) {
        // Republish the complete snapshot. A current-location pin must not replace
        // conditions with a type-specific application-context write.
        if snapshotAccumulator.selectedLocation == nil {
            snapshotAccumulator.selectedLocation = LocationStorageService.shared.loadSelectedLocation()
        }
        if snapshotAccumulator.locations == nil {
            snapshotAccumulator.locations = [location]
        }
        publishCompanionSnapshot()
    }
    
    public func sendConditionsToWatch(_ conditions: ViewingConditions) {
        let selected = LocationStorageService.shared.loadSelectedLocation()
        if let selected {
            snapshotAccumulator.setSelectedLocation(selected)
        }
        let oq: WatchObservingQualityPayload?
        if let selected {
            oq = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
                conditions: conditions,
                selectedLocation: selected
            )
        } else {
            oq = nil
        }
        snapshotAccumulator.setConditions(conditions, observingQuality: oq)
        publishCompanionSnapshot()
    }
    
    public func sendSelectedLocationToWatch(_ location: SelectedLocation) {
        snapshotAccumulator.setSelectedLocation(location)
        publishCompanionSnapshot()
    }
    
    public func sendUnitSystemToWatch(_ system: UnitSystem) {
        snapshotAccumulator.setUnitSystem(system)
        publishCompanionSnapshot()
    }

    private func publishCompanionSnapshot() {
        let snapshot = snapshotAccumulator.snapshot()
        guard let payload = WatchCompanionSnapshotCodec.encode(snapshot) else { return }
        sendViaApplicationContext(payload)
    }
    
    private func sendViaApplicationContext(_ payload: [String: Any]) {
        guard let session = session else { return }

        do {
            try session.updateApplicationContext(payload)
            print("WatchConnectivityService: Updated applicationContext with companion snapshot")
        } catch {
            print("WatchConnectivityService: Failed to update applicationContext: \(error)")
            sendMessage(type: WatchCompanionSnapshotCodec.messageType, payload: payload)
        }
    }
    
    private func sendMessage(type: String, payload: [String: Any]) {
        guard let session = session, session.isReachable else {
            print("WatchConnectivityService: Session not reachable for type: \(type)")
            return
        }
        
        session.sendMessage(
            payload,
            replyHandler: Self.makeReplyHandler(type: type),
            errorHandler: Self.makeErrorHandler(type: type)
        )
    }

    nonisolated private static func makeReplyHandler(type: String) -> ([String: Any]) -> Void {
        { reply in
            print("WatchConnectivityService: Sent \(type), reply: \(reply)")
        }
    }

    nonisolated private static func makeErrorHandler(type: String) -> (any Error) -> Void {
        { error in
            print("WatchConnectivityService: Failed to send \(type): \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let isPaired = session.isPaired
        print("WatchConnectivityService: Activation state: \(activationState.rawValue)")
        Task { @MainActor in
            self.isPaired = isPaired
        }
    }
    
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        print("WatchConnectivityService: Session became inactive")
    }
    
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        print("WatchConnectivityService: Session deactivated")
    }
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        print("WatchConnectivityService: Reachability changed: \(isReachable)")
        Task { @MainActor in
            self.isReachable = isReachable
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        print("WatchConnectivityService: Received message: \(message)")
        handleMessage(message, replyHandler: replyHandler)
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        print("WatchConnectivityService: Received userInfo: \(userInfo)")
        handleMessage(userInfo)
    }
    
    nonisolated private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        if let type = message["type"] as? String {
            switch type {
            case "requestLocations":
                handleRequestLocations(replyHandler: replyHandler)
            case "requestConditions":
                handleRequestConditions(message, replyHandler: replyHandler)
            case "selectedLocationFromWatch":
                if let data = message["selectedLocation"] as? Data,
                   let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) {
                    print("WatchConnectivityService: Received location selection from Watch: \(location.name)")
                    refreshForLocation(location: location)
                }
                replyHandler?(["status": "ok"])
            default:
                print("WatchConnectivityService: Unknown message type: \(type)")
            }
        }
    }
    
    nonisolated private func refreshForLocation(location: SelectedLocation) {
        LocationStorageService.shared.saveSelectedLocation(location)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .watchLocationSelected,
                object: location
            )
        }
    }
    
    nonisolated private func handleRequestLocations(replyHandler: (([String: Any]) -> Void)?) {
        print("WatchConnectivityService: Handling request for locations")
        
        let locations = LocationStorageService.shared.loadSavedLocations()
        let selectedLoc = LocationStorageService.shared.loadSelectedLocation()
        
        var reply: [String: Any] = ["status": "ok"]
        if let data = try? JSONEncoder().encode(locations) {
            reply["locations"] = data
        }
        if let selectedLoc = selectedLoc, let data = try? JSONEncoder().encode(selectedLoc) {
            reply["selectedLocation"] = data
        }
        // Additive: include product-valid iOS saved-location brightness samples so Watch
        // can offline OQ without selecting each pin on the phone first.
        if let samplesData = WatchLocationsBrightnessPriming.encodeSamples(
            WatchLocationsBrightnessPriming.validSamples(for: locations)
        ) {
            reply[WatchLocationsBrightnessPriming.replyPayloadKey] = samplesData
        }
        replyHandler?(reply)
    }
    
    nonisolated private func handleRequestConditions(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?
    ) {
        print("WatchConnectivityService: Handling request for conditions")
        
        guard let replyHandler else { return }
        let replyHandlerBox = WatchReplyHandler(replyHandler)

        // Optional Phase 4C Current Location request context (additive; old phones ignore).
        // Presence of the key means CL intent — never fall through to saved-location OQ
        // when the key is present but decode/validation fails.
        let clRequestIntent = Self.parseCurrentLocationRequestIntent(from: message)
        
        Task {
            var reply: [String: Any] = ["status": "ok"]

            if let conditions = await conditionsForWatchRequest(clRequestIntent: clRequestIntent) {
                let watchConditions = conditions.limitedToTonightCache()
                if let data = try? JSONEncoder().encode(watchConditions) {
                    reply["conditions"] = data
                } else {
                    replyHandlerBox.reply(["status": "error", "message": "Failed to encode conditions"])
                    return
                }

                if let oq = await observingQualityPayload(
                    for: watchConditions,
                    clRequestIntent: clRequestIntent
                ),
                   let oqData = try? JSONEncoder().encode(oq) {
                    reply["observingQuality"] = oqData
                }
            } else {
                replyHandlerBox.reply(["status": "error", "message": "No cached conditions"])
                return
            }
            
            if let selectedLoc = LocationStorageService.shared.loadSelectedLocation(),
               let data = try? JSONEncoder().encode(selectedLoc) {
                reply["selectedLocation"] = data
            }
            
            replyHandlerBox.reply(reply)
        }
    }

    /// How the watch framed this conditions request for OQ purposes.
    private enum CurrentLocationRequestIntent: Sendable {
        /// No `currentLocationRequest` key — saved-location / legacy path.
        case absent
        /// Key present and structurally valid.
        case valid(WatchCurrentLocationRequestContext)
        /// Key present but missing/malformed/invalid — never use saved OQ.
        case invalid
    }

    nonisolated private static func parseCurrentLocationRequestIntent(
        from message: [String: Any]
    ) -> CurrentLocationRequestIntent {
        guard message.keys.contains("currentLocationRequest") else {
            return .absent
        }
        guard let data = message["currentLocationRequest"] as? Data,
              let decoded = try? JSONDecoder().decode(
                WatchCurrentLocationRequestContext.self,
                from: data
              ),
              decoded.isStructurallyValid
        else {
            return .invalid
        }
        return .valid(decoded)
    }

    @MainActor
    private func conditionsForWatchRequest(
        clRequestIntent: CurrentLocationRequestIntent
    ) async -> ViewingConditions? {
        let location: CachedLocation?
        switch clRequestIntent {
        case let .valid(request):
            // Watch-supplied coordinates are authoritative for Phase 4C.
            location = request.asCachedLocation
        case .invalid:
            // Malformed CL context: do not fall back to phone-selected location.
            location = nil
        case .absent:
            location = await watchRequestLocation()
        }
        return await WatchConditionsRequestAcquirer(
            conditionsRepository: conditionsRepository
        ).conditions(
            for: location,
            apiKey: UserDefaults.standard.string(forKey: "n2yoApiKey") ?? "",
            referenceDate: Date()
        )
    }

    /// Builds saved-location (4B) or correlated Current Location (4C) OQ when possible.
    @MainActor
    private func observingQualityPayload(
        for conditions: ViewingConditions,
        clRequestIntent: CurrentLocationRequestIntent
    ) async -> WatchObservingQualityPayload? {
        switch clRequestIntent {
        case let .valid(request):
            // Phase 4C: sample at watch-requested coordinates using process bootstrap only.
            let sample = await currentLocationBrightnessSample(
                latitude: request.latitude,
                longitude: request.longitude
            )
            return WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
                conditions: conditions,
                request: request,
                sample: sample
            )
        case .invalid:
            // Explicit CL attempt that failed validation — do not attach saved-location OQ.
            return nil
        case .absent:
            // Phase 4B: saved-location App Group companion path.
            let selectedLoc = LocationStorageService.shared.loadSelectedLocation()
            guard let selectedLoc else { return nil }
            return WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
                conditions: conditions,
                selectedLocation: selectedLoc
            )
        }
    }

    /// Non-blocking provider reuse — does not start a second atlas load.
    @MainActor
    private func currentLocationBrightnessSample(
        latitude: Double,
        longitude: Double
    ) async -> ModeledZenithBrightnessSample? {
        let provider = await LightPollutionProviderBootstrap.shared.currentProvider()
        guard let provider else { return nil }
        return ModeledZenithBrightnessResolver.sample(
            from: provider,
            latitude: latitude,
            longitude: longitude,
            savedLocationID: nil
        )
    }

    @MainActor
    private func watchRequestLocation() async -> CachedLocation? {
        let selectedLocation = LocationStorageService.shared.loadSelectedLocation()
        let savedLocations = LocationStorageService.shared.loadSavedLocations()
        let cachedConditions = await conditionsRepository.lastKnownCachedConditions()
        return WatchConditionsRequestLocationResolver.resolve(
            selectedLocation: selectedLocation,
            savedLocations: savedLocations,
            cachedConditions: cachedConditions
        )
    }
}
