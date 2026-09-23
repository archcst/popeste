import AppKit
import UniformTypeIdentifiers

/// Saved data and quit-time protection for the editor inside the floating panel.
final class Manager {
    let store: Store
    var draft = PromptDraft()
    init(store: Store) { self.store = store }
    func receive(_ payload: [String: Any]) {
        let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:))
        let original = store.prompts.first { $0.id == id }
        draft = PromptDraft(original: original, body: payload["body"] as? String ?? "", pinned: payload["pinned"] as? Bool ?? false)
    }
    @discardableResult func save() throws -> Prompt {
        let prompt = draft.savedPrompt()
        try store.save(prompt)
        draft = PromptDraft()
        return prompt
    }
    func canLeave() -> Bool {
        guard draft.dirty else { return true }
        let alert = NSAlert(); alert.messageText = "保存未完成的修改？"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "放弃修改")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { try save(); return true } catch { showError(error); return false }
        case .alertThirdButtonReturn: draft = PromptDraft(); return true
        default: return false
        }
    }
    func importFile() throws -> String? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let (values, summary) = store.planImport(try Store.decode(Data(contentsOf: url)))
        let alert = NSAlert(); alert.messageText = "导入预览"
        alert.informativeText = "新增 \(summary.added) 条，跳过正文完全相同的 \(summary.duplicate) 条。现有内容不会被覆盖。"
        alert.addButton(withTitle: "导入"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        try store.commit(values)
        return "已导入 \(summary.added) 条提示词"
    }
    func exportFile() throws -> String? {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Popaste-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try store.export(to: url); return "已导出提示词"
    }
}
