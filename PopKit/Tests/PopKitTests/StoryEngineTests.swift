import Foundation
import Testing
@testable import PopKit

/// Covers `StoryEngine`'s parts not already covered by `StoryPathTests`: the `title`
/// request builder and the reading-level word-count check (PRD §8.7).
struct StoryEngineTests {
    private let kid = KidProfile(firstName: "Sara", readingLevel: .earlyReader, interests: ["dinosaurs"])
    private let settings = ParentSettings(avoidTopics: ["monsters"])

    private func book(pages: [PageContent] = [], bible: StoryBible = .empty) -> Book {
        Book(kidId: kid.id, brief: StoryBrief(interests: ["dinosaurs"], teach: "sharing"), bible: bible, pages: pages, createdAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - request building

    @Test func titleRequestOmitsInputAndUsesEveryFinishedPage() {
        let pages = [PageContent(index: 0, text: "Once upon a time"), PageContent(index: 1, text: "The end.")]
        let request = StoryEngine.titleRequest(book: book(pages: pages), kid: kid, settings: settings)

        #expect(request.mode == .title)
        #expect(request.input == nil)
        #expect(request.pages.map(\.text) == ["Once upon a time", "The end."])
    }

    // MARK: - reading-level validation

    @Test func wordCountIgnoresExtraWhitespace() {
        #expect(StoryEngine.wordCount("  Once   upon\na time ") == 4)
        #expect(StoryEngine.wordCount("") == 0)
    }

    @Test func exceedsReadingLevelComparesAgainstEachLevelsMaxWords() {
        let fifteenWords = Array(repeating: "hop", count: 15).joined(separator: " ")
        let sixteenWords = Array(repeating: "hop", count: 16).joined(separator: " ")
        #expect(StoryEngine.exceedsReadingLevel(fifteenWords, level: .listener) == false)
        #expect(StoryEngine.exceedsReadingLevel(sixteenWords, level: .listener) == true)

        let thirtyWords = Array(repeating: "hop", count: 30).joined(separator: " ")
        #expect(StoryEngine.exceedsReadingLevel(thirtyWords, level: .earlyReader) == false)

        let sixtyOneWords = Array(repeating: "hop", count: 61).joined(separator: " ")
        #expect(StoryEngine.exceedsReadingLevel(sixtyOneWords, level: .reader) == true)
    }
}
