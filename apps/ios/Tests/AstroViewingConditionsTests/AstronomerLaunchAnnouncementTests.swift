import XCTest
@testable import AstroViewingConditions

final class AstronomerLaunchAnnouncementTests: XCTestCase {
    func testUnseenIdentityShowsTheDashboardAnnouncement() throws {
        XCTAssertTrue(AstronomerLaunchAnnouncement.showsAnnouncement(seenIdentity: ""))
        XCTAssertTrue(
            AstronomerLaunchAnnouncement.showsAnnouncement(seenIdentity: "astronomer-launch-v0")
        )

        let suiteName = uniqueSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AstronomerLaunchAnnouncementStore(defaults: defaults)
        XCTAssertTrue(store.showsAnnouncement)
        XCTAssertEqual(store.seenIdentity, "")
    }

    func testDismissingPersistsTheSeenIdentity() throws {
        let suiteName = uniqueSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AstronomerLaunchAnnouncementStore(defaults: defaults)
        let stored = store.record(.dismiss)

        XCTAssertEqual(stored, AstronomerLaunchAnnouncement.identity)
        XCTAssertEqual(store.seenIdentity, "astronomer-launch-v1")
        XCTAssertFalse(store.showsAnnouncement)
        XCTAssertFalse(AstronomerLaunchAnnouncementStore(defaults: defaults).showsAnnouncement)
    }

    func testOpeningPersistsTheSeenIdentity() throws {
        let suiteName = uniqueSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AstronomerLaunchAnnouncementStore(defaults: defaults)
        let stored = store.record(.open)

        XCTAssertEqual(stored, AstronomerLaunchAnnouncement.identity)
        XCTAssertEqual(
            defaults.string(forKey: AstronomerLaunchAnnouncement.defaultsKey),
            AstronomerLaunchAnnouncement.identity
        )
        XCTAssertFalse(store.showsAnnouncement)
        XCTAssertFalse(AstronomerLaunchAnnouncementStore(defaults: defaults).showsAnnouncement)
    }

    func testSeenIdentityHidesTheDashboardAnnouncement() throws {
        let suiteName = uniqueSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            AstronomerLaunchAnnouncement.identity,
            forKey: AstronomerLaunchAnnouncement.defaultsKey
        )

        let store = AstronomerLaunchAnnouncementStore(defaults: defaults)
        XCTAssertEqual(store.seenIdentity, AstronomerLaunchAnnouncement.identity)
        XCTAssertFalse(store.showsAnnouncement)
    }

    func testDashboardAndSettingsUseTheCanonicalURL() {
        XCTAssertEqual(
            AstronomerDestination.canonicalURL.absoluteString,
            "https://x.ai/bot/9orqw_IrUDeEaHo-w68j3"
        )
        XCTAssertEqual(AstronomerDestination.dashboardURL, AstronomerDestination.canonicalURL)
        XCTAssertEqual(AstronomerDestination.settingsURL, AstronomerDestination.canonicalURL)
        XCTAssertEqual(AstronomerSettingsEntry.url, AstronomerDestination.canonicalURL)
    }

    func testSettingsEntryRemainsAvailableAfterTheAnnouncementIsSeen() throws {
        let suiteName = uniqueSuiteName()
        let defaults = try makeDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AstronomerLaunchAnnouncementStore(defaults: defaults)
        store.record(.dismiss)
        XCTAssertFalse(store.showsAnnouncement)

        XCTAssertEqual(AstronomerSettingsEntry.title, "Astronomer")
        XCTAssertEqual(AstronomerSettingsEntry.url, AstronomerDestination.canonicalURL)
        XCTAssertEqual(
            AstronomerSettingsEntry.grokRequirement,
            AstronomerLaunchAnnouncement.grokRequirement
        )
        XCTAssertFalse(AstronomerSettingsEntry.summary.isEmpty)
    }

    func testCopyStatesTheGrokRequirementWithoutImplyingEmbeddedOrSharedState() {
        XCTAssertEqual(AstronomerLaunchAnnouncement.title, "New: Astronomer")
        XCTAssertEqual(AstronomerLaunchAnnouncement.openActionTitle, "Open Astronomer")
        XCTAssertEqual(
            AstronomerLaunchAnnouncement.grokRequirement,
            "Astronomer runs in the Grok Bot app."
        )
        XCTAssertEqual(
            AstronomerSettingsEntry.grokRequirement,
            AstronomerLaunchAnnouncement.grokRequirement
        )
        XCTAssertEqual(
            AstronomerLaunchAnnouncement.summary,
            "Your AI astronomy expert for planning observing nights, choosing targets, getting equipment advice, and asking astronomy questions."
        )
        XCTAssertEqual(
            AstronomerSettingsEntry.summary,
            "AI astronomy expert and observing companion."
        )

        let copy = [
            AstronomerLaunchAnnouncement.title,
            AstronomerLaunchAnnouncement.summary,
            AstronomerLaunchAnnouncement.grokRequirement,
            AstronomerLaunchAnnouncement.openActionTitle,
            AstronomerLaunchAnnouncement.dismissActionTitle,
            AstronomerLaunchAnnouncement.openActionHint,
            AstronomerLaunchAnnouncement.dismissActionHint,
            AstronomerSettingsEntry.title,
            AstronomerSettingsEntry.summary,
            AstronomerSettingsEntry.grokRequirement
        ].joined(separator: "\n").lowercased()

        for phrase in [
            "inside astro conditions",
            "in this app",
            "built-in",
            "built in",
            "optional",
            "automatically",
            "sync",
            "your saved"
        ] {
            XCTAssertFalse(copy.contains(phrase), phrase)
        }
        XCTAssertTrue(copy.contains("leaves astro conditions"))
        XCTAssertTrue(copy.contains("grok bot app"))
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func uniqueSuiteName() -> String {
        "AstronomerLaunchAnnouncementTests.\(UUID().uuidString)"
    }
}
