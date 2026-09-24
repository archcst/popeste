import Foundation
import CoreGraphics

final class StoreTests {
    var root: URL!
    func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func makeStore() throws -> Store { try Store(url: root.appendingPathComponent("prompts.json")) }
    func testPickerScreenGeometry() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: -400, width: 1920, height: 1080),
                       CGRect(x: 200, y: 900, width: 1024, height: 768),
                       CGRect(x: 0, y: 0, width: 400, height: 300)]
        for screen in screens {
            for x in [screen.minX, screen.midX, screen.maxX - 1] {
                for y in [screen.minY, screen.midY, screen.maxY - 20] {
                    let caret = CGRect(x: x, y: y, width: 0, height: 18)
                    let frame = PickerPlacement.frame(caret: caret, mouse: .zero, visibleScreen: screen)
                    XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(frame))
                }
            }
        }
        let screen = screens[0]
        // A collapsed picker near the lower half must not reserve a full list above it.
        let compact = PickerPlacement.frame(caret: nil, mouse: CGPoint(x: 300, y: 300), visibleScreen: screen, desiredSize: CGSize(width: 480, height: 57))
        XCTAssertEqual(compact.minY, 308)
        XCTAssertEqual(compact.height, 57)
        let expanded = PickerPlacement.resizedFrame(compact, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 424))
        XCTAssertEqual(expanded.height, 424)
        XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(expanded))
        let highCompact = PickerPlacement.frame(caret: CGRect(x: 100, y: 700, width: 0, height: 18), mouse: .zero, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 57))
        let highExpanded = PickerPlacement.resizedFrame(highCompact, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 424))
        XCTAssertEqual(highExpanded.maxY, highCompact.maxY)
        let aboveCaret = CGRect(x: 200, y: 500, width: 0, height: 18)
        let aboveCompact = PickerPlacement.frame(caret: aboveCaret, mouse: .zero, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 57))
        XCTAssertEqual(aboveCompact.minY, aboveCaret.maxY + 8)
        let aboveExpanded = PickerPlacement.resizedFrame(aboveCompact, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 250), anchorBottom: true)
        XCTAssertEqual(aboveExpanded.minY, aboveCompact.minY)
        let aboveCollapsed = PickerPlacement.resizedFrame(aboveExpanded, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 57), anchorBottom: true)
        XCTAssertEqual(aboveCollapsed, aboveCompact)
        let topCaret = CGRect(x: 200, y: 865, width: 0, height: 18)
        let belowCompact = PickerPlacement.frame(caret: topCaret, mouse: .zero, visibleScreen: screen, desiredSize: CGSize(width: 480, height: 57))
        XCTAssertEqual(belowCompact.maxY, topCaret.minY - 8)
        let lowCaret = CGRect(x: 100, y: 50, width: 0, height: 18)
        XCTAssertTrue(PickerPlacement.frame(caret: lowCaret, mouse: .zero, visibleScreen: screen).minY > lowCaret.maxY)
        let highCaret = CGRect(x: 100, y: 850, width: 0, height: 18)
        XCTAssertTrue(PickerPlacement.frame(caret: highCaret, mouse: .zero, visibleScreen: screen).maxY < highCaret.minY)
        let middleCaret = CGRect(x: 100, y: 440, width: 0, height: 18)
        let frame = PickerPlacement.frame(caret: middleCaret, mouse: .zero, visibleScreen: screen)
        XCTAssertTrue(frame.maxY < middleCaret.minY || frame.minY > middleCaret.maxY)
        XCTAssertTrue(screen.contains(PickerPlacement.frame(caret: nil, mouse: CGPoint(x: 1439, y: 899), visibleScreen: screen)))
    }
    func testExactRoundTripAndUpdates() throws {
        let store = try makeStore(); var p = Prompt(body: "  第一行\n\n\t缩进 👨‍👩‍👧‍👦\n\"quotes\" \\ 末尾\n")
        try store.save(p); XCTAssertEqual(try makeStore().prompts.first?.body, p.body)
        p.body += "修改"; p.pinned = true; try store.save(p)
        XCTAssertEqual(store.prompts.count, 1); XCTAssertEqual(try makeStore().prompts.first, p)
        try store.delete(p.id); XCTAssertTrue(try makeStore().prompts.isEmpty)
    }
    func testSearchAndRanking() throws {
        let s = try makeStore(); let a = Prompt(body: "Alpha 翻译 SWIFT", uses: 8); let b = Prompt(body: "swift 中文", pinned: true)
        try s.save(a); try s.save(b)
        XCTAssertEqual(s.search("").map(\.id), [b.id, a.id]); XCTAssertEqual(s.search("alpha 翻译").map(\.id), [a.id]); XCTAssertEqual(s.search("SWIFT").count, 2); XCTAssertTrue(s.search("不存在").isEmpty)
    }
    func testImportIsNonDestructive() throws {
        let s = try makeStore(); let p = Prompt(body: "原文"); try s.save(p)
        let (values, report) = s.planImport([Prompt(body: "原文"), Prompt(body: "新正文"), Prompt(body: "第三条")])
        XCTAssertEqual(report.added, 2); XCTAssertEqual(report.duplicate, 1)
        XCTAssertEqual(values.map(\.body), ["原文", "新正文", "第三条"]); XCTAssertEqual(s.prompts, [p])
        try s.commit(values); let file = root.appendingPathComponent("backup.json"); try s.export(to: file)
        XCTAssertEqual(try Store.decode(Data(contentsOf: file)), values)
    }
    func testInvalidInputsAndUnsupportedArchive() throws {
        let s = try makeStore(); XCTAssertThrowsError(try s.save(Prompt(body: " \n")))
        let p = Prompt(body: "b")
        XCTAssertThrowsError(try Store.decode(JSONEncoder().encode(Archive(version: 99, prompts: [p]))))
        XCTAssertThrowsError(try Store.decode(JSONEncoder().encode(Archive(prompts: [p, p]))))
        XCTAssertThrowsError(try Store.decode(Data("broken".utf8)))
    }
    func testMigrationAndConfiguration() throws {
        let destination = root.appendingPathComponent("config/popeste")
        let old = root.appendingPathComponent("legacy.json")
        let id = UUID()
        let legacy: [String: Any] = ["version": 1, "prompts": [["id": id.uuidString, "title": "旧标题", "body": "  多行\n\n    中文 🌟", "pinned": true, "uses": 2, "updated": 1.0]]]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        try data.write(to: old)
        let store = try Store(url: destination.appendingPathComponent("prompts.json"), legacyURL: old)
        XCTAssertEqual(store.prompts.first?.id, id)
        XCTAssertEqual(store.prompts.first?.body, "  多行\n\n    中文 🌟")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("migration-v1-backup.json")), data)
        XCTAssertEqual(try Data(contentsOf: old), data)
        var p = store.prompts[0]; p.body = "更新"; try store.save(p)
        XCTAssertEqual(try Store(url: store.url, legacyURL: old).prompts.first?.body, "更新")
        let encoded = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertTrue(!encoded.contains("title"))
        let suiteName = "PopasteTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcut = Shortcut(code: 0, modifiers: 2048, label: "⌥A")
        defaults.set(try JSONEncoder().encode(shortcut), forKey: "shortcut"); defaults.set(true, forKey: "onboarded")
        let config = try Configuration(directory: destination, legacy: defaults)
        XCTAssertEqual(config.value.shortcut, shortcut); XCTAssertTrue(config.value.onboarded)
        for size in PickerSize.allCases {
            try config.update { $0.pickerSize = size }
            XCTAssertEqual(try Configuration(directory: destination, legacy: defaults).value.pickerSize, size)
            let frame = PickerPlacement.frame(caret: nil, mouse: CGPoint(x: 100, y: 800), visibleScreen: CGRect(x: 0, y: 0, width: 1400, height: 1000), desiredSize: CGSize(width: 480*size.scale, height: 424*size.scale))
            XCTAssertEqual(frame.width, 480*size.scale); XCTAssertEqual(frame.height, 424*size.scale)
        }
        XCTAssertEqual(config.value.resolvedLanguage, Preferences.resolveLanguage(nil))
        XCTAssertEqual(Preferences.resolveLanguage(nil, preferred: ["ja-JP"]), "ja")
        XCTAssertEqual(Preferences.resolveLanguage("system", preferred: ["zh-TW"]), "zh-Hant")
        XCTAssertEqual(Preferences.resolveLanguage(nil, preferred: ["zh-Hans-HK"]), "zh-Hans")
        XCTAssertEqual(Preferences.resolveLanguage(nil, preferred: ["pt-BR", "de-DE"]), "de")
        XCTAssertEqual(Preferences.resolveLanguage(nil, preferred: ["ar"]), "en")
        for language in Preferences.supportedLanguages + ["system"] {
            try config.update { $0.language = language }
            let reloaded = try Configuration(directory: destination, legacy: defaults)
            XCTAssertEqual(reloaded.value.language, language)
            if language != "system" { XCTAssertEqual(reloaded.value.resolvedLanguage, language) }
        }
        XCTAssertEqual(config.value.resolvedNavigationSchemes, ["arrows"])
        for schemes in [["arrows", "vim"], ["emacs", "vim"], []] {
            try config.update { $0.navigationSchemes = schemes }
            XCTAssertEqual(try Configuration(directory: destination, legacy: defaults).value.resolvedNavigationSchemes, schemes)
        }
        XCTAssertEqual(config.value.vimEditing ?? false, false)
        try config.update { $0.vimEditing = true }
        XCTAssertEqual(try Configuration(directory: destination, legacy: defaults).value.vimEditing, true)
        let permission = try FileManager.default.attributesOfItem(atPath: config.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permission?.intValue, 0o600)
        try Data("broken".utf8).write(to: config.url)
        XCTAssertThrowsError(try Configuration(directory: destination, legacy: defaults))
    }
    func testDraftSavePreservesIdentityAndFailedSave() throws {
        let store = try makeStore()
        let original = Prompt(body: "原文\n\n  缩进 🌟", pinned: true, uses: 8)
        try store.save(original)
        var draft = PromptDraft(original: original, body: original.body, pinned: true)
        XCTAssertTrue(!draft.dirty)
        draft.body += "\n修改"; draft.pinned = false
        XCTAssertTrue(draft.dirty)
        XCTAssertEqual(store.prompts, [original])
        let edited = draft.savedPrompt()
        XCTAssertEqual(edited.id, original.id); XCTAssertEqual(edited.uses, 8)
        try store.save(edited)
        XCTAssertEqual(try makeStore().prompts, [edited])
        draft.body = "  \n"
        XCTAssertThrowsError(try store.save(draft.savedPrompt()))
        XCTAssertTrue(draft.dirty); XCTAssertEqual(store.prompts, [edited])
        XCTAssertTrue(!PromptDraft().dirty)
    }
    func testFailedWriteDoesNotChangeMemory() throws {
        let file = root.appendingPathComponent("file"); try Data().write(to: file)
        let s = try Store(url: file.appendingPathComponent("unwritable.json"))
        XCTAssertThrowsError(try s.save(Prompt(body: "b"))); XCTAssertTrue(s.prompts.isEmpty)
    }
}

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \(a) == \(b)", file: file, line: line) }
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try expression() } catch { return }; preconditionFailure("Expected error", file: file, line: line) }
@main struct TestRunner {
    static func main() throws {
        let suite = StoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("screen edges, multiple display coordinates and caret avoidance", suite.testPickerScreenGeometry),
            ("exact round trip and CRUD", suite.testExactRoundTripAndUpdates),
            ("search and pinned ranking", suite.testSearchAndRanking),
            ("non-destructive import/export", suite.testImportIsNonDestructive),
            ("invalid and future archives", suite.testInvalidInputsAndUnsupportedArchive),
            ("legacy migration, config persistence and three sizes", suite.testMigrationAndConfiguration),
            ("draft identity, deferred persistence and invalid save", suite.testDraftSavePreservesIdentityAndFailedSave),
            ("failed write is atomic", suite.testFailedWriteDoesNotChangeMemory)
        ]
        for (name, test) in cases { try suite.setUpWithError(); try test(); try suite.tearDownWithError(); print("PASS: \(name)") }
    }
}
