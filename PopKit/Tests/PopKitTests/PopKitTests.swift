import Testing
@testable import PopKit

@Test func packageReportsItsVersion() {
    #expect(PopKit.version == "0.1.0")
}
