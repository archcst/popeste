import AppKit

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
        let alert = NSAlert(); alert.messageText = tr("保存未完成的修改？")
        alert.addButton(withTitle: tr("保存")); alert.addButton(withTitle: tr("继续编辑")); alert.addButton(withTitle: tr("放弃修改"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { try save(); return true } catch { showError(error); return false }
        case .alertThirdButtonReturn: draft = PromptDraft(); return true
        default: return false
        }
    }
}
