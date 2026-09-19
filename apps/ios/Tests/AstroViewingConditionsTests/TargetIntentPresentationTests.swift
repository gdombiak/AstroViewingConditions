import SharedCode
import XCTest
@testable import AstroViewingConditions

final class TargetIntentPresentationTests: XCTestCase {

    func testOnlyChallengeTargetsRequestIntentBadges() {
        XCTAssertTrue(TargetIntentPresentation.showsBadge(for: .challenge))
        XCTAssertEqual(TargetIntentPresentation.badgeText(for: .challenge), "Challenge")
        XCTAssertNil(TargetIntentPresentation.detailGuidance(for: .challenge))
        XCTAssertFalse(TargetIntentPresentation.showsBadge(for: .easy))
        XCTAssertFalse(TargetIntentPresentation.showsBadge(for: .standard))
        XCTAssertNil(TargetIntentPresentation.badgeText(for: .easy))
        XCTAssertNil(TargetIntentPresentation.badgeText(for: .standard))
        XCTAssertNil(TargetIntentPresentation.detailGuidance(for: .easy))
        XCTAssertNil(TargetIntentPresentation.detailGuidance(for: .standard))
    }

}
