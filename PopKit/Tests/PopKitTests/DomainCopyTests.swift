import Foundation
import Testing
@testable import PopKit

/// Covers the copy helpers and reading-level details that DomainTests leaves out (REVIEW R-28).
struct DomainCopyTests {
    private let page = PageContent(
        index: 1, version: 3, text: "Old words", artPrompt: "a fox",
        stillPath: "u/b/p1.png", layers: PageLayers(platePath: "u/b/plate.png", cutouts: [Cutout(characterId: "fox", path: "u/b/fox.png")]),
        motion: MotionParts(scene: "meadow", motion: "grass sways"), clipPath: "u/b/p1.mp4"
    )

    @Test func eachPageCopyChangesOnlyItsOwnField() {
        let stillCopy = page.with(stillPath: "new.png")
        #expect(stillCopy.stillPath == "new.png")
        #expect(stillCopy == PageContent(id: page.id, index: 1, version: 3, text: page.text, artPrompt: page.artPrompt, stillPath: "new.png", layers: page.layers, motion: page.motion, clipPath: page.clipPath))

        let layersCopy = page.with(layers: nil)
        #expect(layersCopy.layers == nil && layersCopy.stillPath == page.stillPath && layersCopy.clipPath == page.clipPath)

        let pond = MotionParts(scene: "pond", motion: "ripples")
        let motionCopy = page.with(motion: pond)
        #expect(motionCopy.motion == pond && motionCopy.layers == page.layers && motionCopy.text == page.text)

        let clipCopy = page.with(clipPath: nil)
        #expect(clipCopy.clipPath == nil && clipCopy.motion == page.motion && clipCopy.stillPath == page.stillPath)

        let textCopy = page.with(text: "New words")
        #expect(textCopy.text == "New words" && textCopy.stillPath == page.stillPath && textCopy.clipPath == page.clipPath)

        for copy in [stillCopy, layersCopy, motionCopy, clipCopy, textCopy] {
            #expect(copy.id == page.id && copy.index == page.index && copy.version == page.version)
            #expect(copy.artPrompt == page.artPrompt)
        }
    }

    @Test func copyingAPageLeavesTheOriginalUntouched() {
        _ = page.with(text: "Changed").with(clipPath: nil)
        #expect(page.text == "Old words")
        #expect(page.clipPath == "u/b/p1.mp4")
    }

    @Test func bookCopiesKeepEverythingElse() {
        let book = SampleBooks.fox
        let fewer = book.with(pages: Array(book.pages.prefix(2)))
        #expect(fewer.pages.count == 2)
        #expect(fewer.id == book.id && fewer.bible == book.bible && fewer.status == book.status)

        let bible = StoryBible(title: "Fox", setting: "forest", directions: ["make it rain"])
        let rebibled = book.with(bible: bible)
        #expect(rebibled.bible == bible)
        #expect(rebibled.pages == book.pages && rebibled.createdAt == book.createdAt)
    }

    @Test func finishingABookSetsStatusTitleCoverAndTime() {
        let book = SampleBooks.fox
        let done = Date(timeIntervalSince1970: 1_800_000_000)
        let finished = book.finished(title: "The Brave Fox", coverPath: "u/b/cover.png", at: done)
        #expect(finished.status == .finished)
        #expect(finished.title == "The Brave Fox")
        #expect(finished.coverPath == "u/b/cover.png")
        #expect(finished.finishedAt == done)
        #expect(finished.pages == book.pages && finished.createdAt == book.createdAt && finished.id == book.id)
    }

    @Test func readingLevelsMatchThePrdTable() {
        #expect(ReadingLevel.allCases.map(\.ages) == ["3–4", "5–6", "7–8"])
        #expect(ReadingLevel.allCases.map(\.title) == ["Listener", "Early reader", "Reader"])
        #expect(ReadingLevel.listener.sentencesPerPage == 1...2)
        #expect(ReadingLevel.earlyReader.sentencesPerPage == 2...3)
        #expect(ReadingLevel.reader.sentencesPerPage == 1...5)
    }

    @Test func olderReadersGetSmallerTextAndMoreWords() {
        let levels = ReadingLevel.allCases
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0.minimumTextSize > $1.minimumTextSize })
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0.maxWordsPerPage < $1.maxWordsPerPage })
    }

    @Test func parentSettingsDefaultToNoOverride() {
        let settings = ParentSettings()
        #expect(settings.avoidTopics.isEmpty && settings.readingLevel == nil && settings.language == "en")
    }
}
