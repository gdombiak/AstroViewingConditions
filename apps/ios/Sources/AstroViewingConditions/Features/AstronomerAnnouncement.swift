import Foundation

/// Canonical Astronomer destination. Dashboard and Settings both open this URL.
enum AstronomerDestination {
    static let canonicalURL = URL(string: "https://x.ai/bot/9orqw_IrUDeEaHo-w68j3")!
    static let dashboardURL = canonicalURL
    static let settingsURL = canonicalURL
}

/// Dashboard launch notice. Stored once the user dismisses it or opens Astronomer from it.
enum AstronomerLaunchAnnouncement {
    static let identity = "astronomer-launch-v1"
    static let defaultsKey = "astronomerLaunchAnnouncement.seenIdentity"

    static let title = "New: Astronomer"
    static let summary = "Your AI astronomy expert for planning observing nights, choosing targets, getting equipment advice, and asking astronomy questions."
    static let grokRequirement = "Astronomer runs in the Grok Bot app."
    static let openActionTitle = "Open Astronomer"
    static let dismissActionTitle = "Dismiss"
    static let openActionHint = "Leaves Astro Conditions and opens Astronomer in the Grok Bot app."
    static let dismissActionHint = "Hides this announcement."

    enum Action: Equatable {
        case dismiss
        case open
    }

    static func showsAnnouncement(seenIdentity: String) -> Bool {
        seenIdentity != identity
    }

    static func identityToStore(after action: Action) -> String {
        switch action {
        case .dismiss, .open:
            return identity
        }
    }
}

struct AstronomerLaunchAnnouncementStore {
    let defaults: UserDefaults

    var seenIdentity: String {
        defaults.string(forKey: AstronomerLaunchAnnouncement.defaultsKey) ?? ""
    }

    var showsAnnouncement: Bool {
        AstronomerLaunchAnnouncement.showsAnnouncement(seenIdentity: seenIdentity)
    }

    @discardableResult
    func record(_ action: AstronomerLaunchAnnouncement.Action) -> String {
        let identity = AstronomerLaunchAnnouncement.identityToStore(after: action)
        defaults.set(identity, forKey: AstronomerLaunchAnnouncement.defaultsKey)
        return identity
    }
}

/// Permanent Settings entry. Not gated by launch-announcement dismissal.
enum AstronomerSettingsEntry {
    static let title = "Astronomer"
    static let summary = "AI astronomy expert and observing companion."
    static let grokRequirement = AstronomerLaunchAnnouncement.grokRequirement
    static let systemImage = "star.bubble"
    static let url = AstronomerDestination.settingsURL
}
