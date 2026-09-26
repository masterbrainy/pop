import Foundation
import Testing
@testable import PopKit

struct DomainTests {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test func readingLevelsUseTheWireNamesAndPrdLimits() throws {
        #expect(try encoder.encode([ReadingLevel.earlyReader]) == Data(#"["early_reader"]"#.utf8))
        #expect(ReadingLevel.listener.maxWordsPerPage == 15)
        #expect(ReadingLevel.earlyReader.maxWordsPerPage == 30)
        #expect(ReadingLevel.reader.maxWordsPerPage == 60)
        #expect(ReadingLevel.listener.minimumTextSize == 32)
        #expect(ReadingLevel.earlyReader.minimumTextSize == 28)
        #expect(ReadingLevel.reader.minimumTextSize == 24)
    }

    @Test func bookRoundTripsThroughJson() throws {
        let book = SampleBooks.fox
        let decoded = try decoder.decode(Book.self, from: encoder.encode(book))
        #expect(decoded == book)
    }

    @Test func pageContentUsesCamelCaseKeys() throws {
        let page = PageContent(index: 0, text: "Hi", artPrompt: "a fox", stillPath: "u/b/p0.png")
        let json = try #require(String(data: encoder.encode(page), encoding: .utf8))
        #expect(json.contains(#""artPrompt":"a fox""#))
        #expect(json.contains(#""stillPath":"u\/b\/p0.png""#) || json.contains(#""stillPath":"u/b/p0.png""#))
        #expect(json.contains(#""version":1"#))
    }

    @Test func revisingAPageBumpsItsVersionAndClearsDerivedMedia() {
        let page = PageContent(index: 2, text: "Old", artPrompt: "old", stillPath: "p.png", motion: MotionParts(scene: "s", motion: "m"), clipPath: "c.mp4")
        let revised = page.revised(text: "New", artPrompt: "new")
        #expect(revised.version == page.version + 1)
        #expect(revised.id == page.id)
        #expect(revised.text == "New" && revised.artPrompt == "new")
        #expect(revised.stillPath == nil && revised.motion == nil && revised.clipPath == nil && revised.layers == nil)
    }

    @Test func coverLineAddsTheKidsName() {
        #expect(Book.coverLine(title: "Rex Learns to Share", firstName: "Sara") == "Rex Learns to Share, a story for Sara")
    }

    @Test func sampleBookHasFivePagesInOrder() {
        #expect(SampleBooks.fox.pages.map(\.index) == [0, 1, 2, 3, 4])
        #expect(SampleBooks.fox.pages.allSatisfy { !$0.text.isEmpty })
    }
}

struct MotionPromptBuilderTests {
    @Test func buildsTheFixedTemplateWithOneGentleClause() {
        let prompt = MotionPromptBuilder.prompt(scene: "sunny meadow with a small red fox under a big oak tree", motion: "The fox's tail swishes slowly")
        #expect(prompt == "The same sunny meadow with a small red fox under a big oak tree, the same locked-off, still camera. The fox's tail swishes slowly. Nothing new enters the scene. Continuous slow motion, no cuts.")
    }

    @Test func tidiesPunctuationAndLeadingArticles() {
        let prompt = MotionPromptBuilder.prompt(scene: "  The quiet pond at dusk. ", motion: "ripples spread gently across the water.")
        #expect(prompt == "The same quiet pond at dusk, the same locked-off, still camera. Ripples spread gently across the water. Nothing new enters the scene. Continuous slow motion, no cuts.")
    }

    @Test func fallsBackToAGentleDefaultWhenMotionIsEmpty() {
        let prompt = MotionPromptBuilder.prompt(scene: "cozy bedroom", motion: "   ")
        #expect(prompt.contains("Everything sways very gently."))
    }
}
