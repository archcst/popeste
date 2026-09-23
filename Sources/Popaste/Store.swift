import Foundation

struct Prompt: Codable, Identifiable, Equatable {
    var id = UUID()
    var body: String
    var pinned = false
    var uses = 0
    var updated = Date()
    var excerpt: String { body.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
struct Archive: Codable { var version = 2; var prompts: [Prompt] }
struct ImportSummary { var added = 0; var duplicate = 0 }
enum StoreError: LocalizedError {
    case invalid, version
    var errorDescription: String? { self == .invalid ? "提示词正文不能为空，或文件中存在重复 ID。" : "不支持此备份版本。" }
}
final class Store {
    private(set) var prompts: [Prompt] = []
    let url: URL
    var onChange: (() -> Void)?
    init(url: URL? = nil, legacyURL: URL? = nil) throws {
        self.url = url ?? LocalFiles.directory.appendingPathComponent("prompts.json")
        if (url == nil || legacyURL != nil) && !FileManager.default.fileExists(atPath: self.url.path) {
            let legacy = legacyURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Popaste/prompts.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                let data = try Data(contentsOf: legacy)
                let migrated = try Self.decode(data)
                let backup = self.url.deletingLastPathComponent().appendingPathComponent("migration-v1-backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try LocalFiles.write(data, to: backup) }
                try commit(migrated)
            } else { try commit([]) }
        }
        if FileManager.default.fileExists(atPath: self.url.path) { prompts = try Self.decode(Data(contentsOf: self.url)) }
    }
    static func decode(_ data: Data) throws -> [Prompt] {
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard [1, 2].contains(archive.version) else { throw StoreError.version }
        guard Set(archive.prompts.map(\.id)).count == archive.prompts.count,
              archive.prompts.allSatisfy({ valid($0) }) else { throw StoreError.invalid }
        return archive.prompts
    }
    static func valid(_ prompt: Prompt) -> Bool { !prompt.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func commit(_ values: [Prompt]) throws {
        let data = try JSONEncoder().encode(Archive(prompts: values))
        try LocalFiles.write(data, to: url)
        prompts = values; onChange?()
    }
    func save(_ prompt: Prompt) throws {
        guard Self.valid(prompt) else { throw StoreError.invalid }
        var values = prompts
        if let index = values.firstIndex(where: { $0.id == prompt.id }) { values[index] = prompt } else { values.append(prompt) }
        try commit(values)
    }
    func delete(_ id: UUID) throws { try commit(prompts.filter { $0.id != id }) }
    func used(_ id: UUID) throws {
        guard var p = prompts.first(where: { $0.id == id }) else { return }
        if p.uses < Int.max { p.uses += 1 }; try save(p)
    }
    func search(_ query: String) -> [Prompt] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return prompts.filter { p in words.allSatisfy { p.body.localizedStandardContains($0) } }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.uses != $1.uses { return $0.uses > $1.uses }
            if $0.updated != $1.updated { return $0.updated > $1.updated }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    func planImport(_ incoming: [Prompt]) -> ([Prompt], ImportSummary) {
        var result = prompts; var summary = ImportSummary()
        for var p in incoming {
            if result.contains(where: { $0.body == p.body }) { summary.duplicate += 1; continue }
            p.id = UUID(); p.uses = 0; result.append(p); summary.added += 1
        }
        return (result, summary)
    }
    func export(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Archive(prompts: prompts)).write(to: url, options: .atomic)
    }
}

/// Drafts survive hiding the panel, and become persistent only after a successful save.
struct PromptDraft {
    var original: Prompt?
    var body = ""
    var pinned = false
    var dirty: Bool { body != (original?.body ?? "") || pinned != (original?.pinned ?? false) }
    func savedPrompt() -> Prompt {
        var prompt = original ?? Prompt(body: "")
        prompt.body = body; prompt.pinned = pinned; prompt.updated = Date()
        return prompt
    }
}
