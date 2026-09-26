import Foundation

/// Fixed content for tests only; the app itself ships no built-in child or book.
public enum SampleBooks {
    public static let kid = KidProfile(
        id: UUID(uuidString: "6F0C2E1A-6A51-4D5B-9B8E-0A1B2C3D4E5F")!,
        firstName: "Sara",
        readingLevel: .earlyReader,
        interests: ["foxes", "stars"]
    )

    public static let fox: Book = {
        let texts = [
            "Under the big oak tree, a little red fox named Pip curled up for a nap.",
            "A leaf floated down and tickled Pip's nose. \"Achoo!\" Pip woke up with a grin.",
            "Pip followed the leaf across the meadow, past the daisies and the humming bees.",
            "At the pond, a friendly frog said, \"Let's race the leaf to the other side!\"",
            "They splashed and laughed until the sky turned pink. Then Pip trotted home to bed.",
        ]
        let pages = texts.enumerated().map { index, text in
            PageContent(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                index: index,
                text: text,
                artPrompt: "A little red fox named Pip. \(text)",
                stillPath: "asset:sample-fox-\(index)"
            )
        }
        return Book(
            id: UUID(uuidString: "B00C0000-0000-4000-8000-000000000001")!,
            kidId: kid.id,
            brief: StoryBrief(interests: kid.interests, teach: "being curious"),
            bible: StoryBible(
                title: "Pip and the Floating Leaf",
                setting: "a sunny meadow with a big oak tree and a pond",
                characters: [Character(id: "pip", name: "Pip", description: "a small red fox with a white-tipped tail and a big grin")]
            ),
            pages: pages,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }()
}
