import PopKit
import SwiftUI

/// Parent settings (ROADMAP Phase 6): the kid's first name, reading level and interests, and
/// topics to avoid. Only the first name and interests are stored about the kid (PRD §10).
struct ParentSettingsView: View {
    let kid: KidProfile
    let settings: ParentSettings
    let onSave: (KidProfile, ParentSettings) -> Void
    var onDone: () -> Void = {}

    @State private var firstName: String
    @State private var level: ReadingLevel
    @State private var interests: String
    @State private var avoid: String
    @State private var readAlong: Bool

    init(kid: KidProfile, settings: ParentSettings, readAlong: Bool, onSave: @escaping (KidProfile, ParentSettings) -> Void, onDone: @escaping () -> Void = {}) {
        self.kid = kid
        self.settings = settings
        self.onSave = onSave
        self.onDone = onDone
        _firstName = State(initialValue: kid.firstName)
        _level = State(initialValue: settings.readingLevel ?? kid.readingLevel)
        _interests = State(initialValue: kid.interests.joined(separator: ", "))
        _avoid = State(initialValue: settings.avoidTopics.joined(separator: ", "))
        _readAlong = State(initialValue: readAlong)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your kid") {
                    TextField("First name only", text: $firstName)
                        .textContentType(.givenName)
                    Picker("Reading level", selection: $level) {
                        ForEach(ReadingLevel.allCases, id: \.self) { level in
                            Text("\(level.title) (\(level.ages))").tag(level)
                        }
                    }
                    TextField("Interests, separated by commas", text: $interests, axis: .vertical)
                }
                Section {
                    TextField("Storms, spiders, getting lost…", text: $avoid, axis: .vertical)
                } header: {
                    Text("Topics to leave out")
                } footer: {
                    Text("Stories always stay kind and safe. These are extra things your kid would rather not meet.")
                }
                Section {
                    Toggle("Read pages aloud", isOn: $readAlong)
                } footer: {
                    Text("Pop! uses the iPhone's own voice and highlights each word as it reads.")
                }
                Section("Privacy") {
                    Label("Your voice is never recorded or stored.", systemImage: "mic.slash")
                    Label("Only a first name and interests are saved.", systemImage: "person.crop.circle")
                    Label("Stories never include surnames, addresses, schools or phone numbers.", systemImage: "lock.shield")
                }
                .font(.footnote)
            }
            .navigationTitle("Parent settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        onDone()
                    }
                }
            }
        }
    }

    private func save() {
        let name = firstName.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? kid.firstName
        let updatedKid = KidProfile(id: kid.id, firstName: name, readingLevel: level, interests: Self.list(interests))
        let updatedSettings = ParentSettings(avoidTopics: Self.list(avoid), readingLevel: level, language: settings.language)
        UserDefaults.standard.set(readAlong, forKey: ParentPreferences.readAlongKey)
        onSave(updatedKid, updatedSettings)
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

enum ParentPreferences {
    static let readAlongKey = "readAlong"
    static var readAlong: Bool { UserDefaults.standard.object(forKey: readAlongKey) as? Bool ?? true }
}
